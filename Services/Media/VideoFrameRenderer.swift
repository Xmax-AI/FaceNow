//
//  VideoFrameRenderer.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreImage
import CoreMedia
import Foundation

/// Allocates bounded IOSurface buffers and normalizes video without changing its orientation.
/// Instances are confined to the owning producer or extension queue.
final class VideoFrameRenderer {

    /// The renderer and color space reused between frames.
    private let context = CIContext(options: [.cacheIntermediates: false])

    /// The BT.709 color space used consistently for rendered video.
    private let colorSpace = CGColorSpace(name: CGColorSpace.itur_709)!

    /// The fixed video description and bounded output buffer pool.
    let formatDescription: CMVideoFormatDescription

    /// The bounded IOSurface-compatible output buffer pool owned by this renderer.
    private let pool: CVPixelBufferPool

    /// The output bounds derived from the caller's video format.
    private let bounds: CGRect

    /// The caller-owned output contract for this renderer instance.
    private let format: VideoFormat

    /// The offline canvas and optional centered artwork cached for this output format.
    private let waitingImage: CIImage

    /// The caller-supplied artwork cached in output pixel coordinates, applied only to video input.
    private let overlay: CIImage?

    /// Creates a reusable renderer with optional output-coordinate artwork and a bounded buffer pool.
    init(
        format: VideoFormat,
        overlay: CGImage? = nil,
        waitingArtwork: CGImage? = nil
    ) throws {
        self.format = format
        self.overlay = overlay.map { CIImage(cgImage: $0) }
        bounds = CGRect(
            x: 0,
            y: 0,
            width: format.width,
            height: format.height
        )
        var pool: CVPixelBufferPool?
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: format.width,
            kCVPixelBufferHeightKey as String: format.height,
            kCVPixelBufferPixelFormatTypeKey as String: format.pixelFormat,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        try Self.check(
            CVPixelBufferPoolCreate(
                nil,
                nil,
                attributes as CFDictionary,
                &pool
            )
        )
        guard let pool else { throw RendererError.allocation }
        self.pool = pool
        var prototype: CVPixelBuffer?
        try Self.check(
            CVPixelBufferPoolCreatePixelBuffer(
                nil,
                pool,
                &prototype
            )
        )
        guard let prototype else { throw RendererError.allocation }
        Self.attachColorMetadata(to: prototype)
        var description: CMVideoFormatDescription?
        try Self.check(
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: nil,
                imageBuffer: prototype,
                formatDescriptionOut: &description
            )
        )
        guard let description else { throw RendererError.allocation }
        formatDescription = description
        waitingImage = Self.makeWaitingImage(
            bounds: bounds,
            artwork: waitingArtwork
        )
    }

    /// Reuses compatible buffers only without artwork; otherwise normalizes and composites into owned output.
    /// Format matching includes color, aperture and aspect-ratio metadata without modifying the input.
    func normalize(
        _ pixelBuffer: CVPixelBuffer
    ) throws -> CVPixelBuffer {
        if overlay == nil,
            CVPixelBufferGetWidth(pixelBuffer) == format.width,
            CVPixelBufferGetHeight(pixelBuffer) == format.height,
            CVPixelBufferGetPixelFormatType(pixelBuffer) == format.pixelFormat,
            CVPixelBufferGetPlaneCount(pixelBuffer) == 2,
            CVPixelBufferGetIOSurface(pixelBuffer) != nil,
            CMVideoFormatDescriptionMatchesImageBuffer(
                formatDescription,
                imageBuffer: pixelBuffer
            )
        {
            return pixelBuffer
        }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let resized = image.transformed(
            by: CGAffineTransform(
                scaleX: bounds.width / image.extent.width,
                y: bounds.height / image.extent.height
            )
        )
        return try render(overlay?.composited(over: resized) ?? resized)
    }

    /// Returns the cached offline artwork when generated video is unavailable.
    func waiting() throws -> CVPixelBuffer {
        try render(waitingImage)
    }

    /// Creates color bars with a moving white marker to verify live transport.
    func testPattern(
        at seconds: TimeInterval
    ) throws -> CVPixelBuffer {
        let colors: [CIColor] = [.white, .yellow, .cyan, .green, .magenta, .red, .blue]
        var image = CIImage(color: .black).cropped(to: bounds)
        let stripeWidth = bounds.width / CGFloat(colors.count)
        for (index, color) in colors.enumerated() {
            let stripe = CIImage(color: color).cropped(
                to: CGRect(
                    x: CGFloat(index) * stripeWidth,
                    y: 0,
                    width: stripeWidth + 1,
                    height: bounds.height
                )
            )
            image = stripe.composited(over: image)
        }
        let marker = CIImage(color: .white).cropped(
            to: CGRect(
                x: seconds.truncatingRemainder(dividingBy: 4) / 4 * (bounds.width - 32),
                y: 32,
                width: 32,
                height: 80
            )
        )
        return try render(marker.composited(over: image))
    }

    /// Wraps a host-clock frame with the negotiated source or sink duration.
    func sampleBuffer(
        _ pixelBuffer: CVPixelBuffer,
        at time: CMTime,
        duration: CMTime? = nil
    ) throws -> CMSampleBuffer {
        var description: CMVideoFormatDescription?
        try Self.check(
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: nil,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &description
            )
        )
        guard let description else { throw RendererError.allocation }
        var timing = CMSampleTimingInfo(
            duration: duration ?? format.frameDuration,
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        try Self.check(
            CMSampleBufferCreateForImageBuffer(
                allocator: nil,
                imageBuffer: pixelBuffer,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: description,
                sampleTiming: &timing,
                sampleBufferOut: &sample
            )
        )
        guard let sample else { throw RendererError.allocation }
        return sample
    }

    /// Renders into a buffer without allowing unbounded allocation during backpressure.
    private func render(
        _ image: CIImage
    ) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let auxiliary = [kCVPixelBufferPoolAllocationThresholdKey as String: 8] as CFDictionary
        try Self.check(
            CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
                nil,
                pool,
                auxiliary,
                &buffer
            )
        )
        guard let buffer else { throw RendererError.allocation }
        context.render(
            image,
            to: buffer,
            bounds: bounds,
            colorSpace: colorSpace
        )
        Self.attachColorMetadata(to: buffer)
        return buffer
    }

    /// Keeps the advertised stream and actual buffers on the same video color standard.
    private static func attachColorMetadata(
        to buffer: CVPixelBuffer
    ) {
        CVBufferSetAttachment(
            buffer,
            kCVImageBufferColorPrimariesKey,
            kCVImageBufferColorPrimaries_ITU_R_709_2,
            .shouldPropagate
        )
        CVBufferSetAttachment(
            buffer,
            kCVImageBufferTransferFunctionKey,
            kCVImageBufferTransferFunction_ITU_R_709_2,
            .shouldPropagate
        )
        CVBufferSetAttachment(
            buffer,
            kCVImageBufferYCbCrMatrixKey,
            kCVImageBufferYCbCrMatrix_ITU_R_709_2,
            .shouldPropagate
        )
    }

    /// Fits offline artwork at the center, capped at 28 percent of the canvas's shorter edge.
    /// A white canvas preserves the supplied image's background; callers without artwork keep the neutral canvas.
    private static func makeWaitingImage(
        bounds: CGRect,
        artwork: CGImage?
    ) -> CIImage {
        let background = artwork == nil
            ? CIColor(red: 241.0 / 255, green: 243.0 / 255, blue: 244.0 / 255)
            : .white
        let canvas = CIImage(color: background).cropped(to: bounds)
        guard let artwork else { return canvas }
        let image = CIImage(cgImage: artwork)
        let size = min(bounds.width, bounds.height) * 0.28
        let scale = size / max(image.extent.width, image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let centered = scaled.transformed(
            by: CGAffineTransform(
                translationX: bounds.midX - scaled.extent.midX,
                y: bounds.midY - scaled.extent.midY
            )
        )
        return centered.composited(over: canvas).cropped(to: bounds)
    }

    /// Converts framework status codes into actionable errors.
    private static func check(
        _ status: OSStatus
    ) throws {
        guard status == noErr else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status)
            )
        }
    }
}

/// A framework failed to provide an expected media object.
enum RendererError: Error {

    /// CoreVideo could not provide a required output buffer or media description.
    case allocation
}
