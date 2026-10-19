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
import ImageIO
import Foundation

/// Allocates bounded IOSurface buffers and normalizes video without changing its orientation.
/// Instances are confined to the owning producer or extension queue.
final class VideoFrameRenderer {
    /// The renderer and color space reused between frames.
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.itur_709)!

    /// The fixed video description and bounded output buffer pool.
    let formatDescription: CMVideoFormatDescription
    private let pool: CVPixelBufferPool

    /// The output bounds and cached offline image.
    private let bounds = CGRect(x: 0, y: 0, width: CameraConfiguration.width, height: CameraConfiguration.height)
    private let waitingImage: CIImage

    /// Creates a reusable NV12 renderer or reports a CoreVideo allocation failure.
    init() throws {
        var pool: CVPixelBufferPool?
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: CameraConfiguration.width,
            kCVPixelBufferHeightKey as String: CameraConfiguration.height,
            kCVPixelBufferPixelFormatTypeKey as String: CameraConfiguration.pixelFormat,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        try Self.check(CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool))
        guard let pool else { throw RendererError.allocation }
        self.pool = pool
        var prototype: CVPixelBuffer?
        try Self.check(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &prototype))
        guard let prototype else { throw RendererError.allocation }
        Self.attachColorMetadata(to: prototype)
        var description: CMVideoFormatDescription?
        try Self.check(CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil, imageBuffer: prototype, formatDescriptionOut: &description
        ))
        guard let description else { throw RendererError.allocation }
        formatDescription = description
        waitingImage = try Self.makeWaitingImage()
    }

    /// Maps the complete input onto the model-sized camera canvas without cropping or padding.
    /// Smaller landscape generation frames retain their aspect ratio when resized to this canvas.
    func normalize(_ pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let resized = image.transformed(by: CGAffineTransform(
            scaleX: bounds.width / image.extent.width, y: bounds.height / image.extent.height
        ))
        return try render(resized)
    }

    /// Returns a mirrored offline card without exposing the last generated image indefinitely.
    func waiting() throws -> CVPixelBuffer {
        try render(waitingImage)
    }

    /// Creates color bars with a moving white marker to verify live transport.
    func testPattern(at seconds: TimeInterval) throws -> CVPixelBuffer {
        let colors: [CIColor] = [.white, .yellow, .cyan, .green, .magenta, .red, .blue]
        var image = CIImage(color: .black).cropped(to: bounds)
        let stripeWidth = bounds.width / CGFloat(colors.count)
        for (index, color) in colors.enumerated() {
            let stripe = CIImage(color: color).cropped(to: CGRect(
                x: CGFloat(index) * stripeWidth, y: 0, width: stripeWidth + 1, height: bounds.height
            ))
            image = stripe.composited(over: image)
        }
        let marker = CIImage(color: .white).cropped(to: CGRect(
            x: seconds.truncatingRemainder(dividingBy: 4) / 4 * (bounds.width - 32),
            y: 32, width: 32, height: 80
        ))
        return try render(marker.composited(over: image))
    }

    /// Wraps a host-clock frame with the negotiated source or sink duration.
    func sampleBuffer(_ pixelBuffer: CVPixelBuffer, at time: CMTime, duration: CMTime = CameraConfiguration.frameDuration) throws -> CMSampleBuffer {
        var description: CMVideoFormatDescription?
        try Self.check(CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &description
        ))
        guard let description else { throw RendererError.allocation }
        var timing = CMSampleTimingInfo(
            duration: duration, presentationTimeStamp: time, decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        try Self.check(CMSampleBufferCreateForImageBuffer(
            allocator: nil, imageBuffer: pixelBuffer, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: description,
            sampleTiming: &timing, sampleBufferOut: &sample
        ))
        guard let sample else { throw RendererError.allocation }
        return sample
    }

    /// Renders into a buffer without allowing unbounded allocation during backpressure.
    private func render(_ image: CIImage) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let auxiliary = [kCVPixelBufferPoolAllocationThresholdKey as String: 8] as CFDictionary
        try Self.check(CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, auxiliary, &buffer))
        guard let buffer else { throw RendererError.allocation }
        context.render(image, to: buffer, bounds: bounds, colorSpace: colorSpace)
        Self.attachColorMetadata(to: buffer)
        return buffer
    }

    /// Keeps the advertised stream and actual buffers on the same video color standard.
    private static func attachColorMetadata(to buffer: CVPixelBuffer) {
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
    }

    /// Builds the mirrored waiting card from the same wordmark used by the home screen.
    private static func makeWaitingImage() throws -> CIImage {
#if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: "xmax-wordmark", withExtension: "png",
                                    subdirectory: "Assets.xcassets/XmaxWordmark.imageset")
#else
        let url = Bundle.main.url(forResource: "xmax-wordmark", withExtension: "png")
#endif
        guard let url,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let logo = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw RendererError.logoUnavailable
        }
        let width = CGFloat(CameraConfiguration.width)
        let height = CGFloat(CameraConfiguration.height)
        let logoWidth: CGFloat = 320
        let logoHeight = logoWidth * CGFloat(logo.height) / CGFloat(logo.width)
        let image = CIImage(cgImage: logo)
            .transformed(by: CGAffineTransform(scaleX: logoWidth / CGFloat(logo.width),
                                               y: logoHeight / CGFloat(logo.height)))
            .transformed(by: CGAffineTransform(translationX: (width - logoWidth) / 2,
                                               y: (height - logoHeight) / 2))
        let background = CIImage(color: CIColor(red: 241.0 / 255, green: 243.0 / 255, blue: 244.0 / 255))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        return image.composited(over: background).transformed(by: CGAffineTransform(
            a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0
        ))
    }

    /// Converts framework status codes into actionable errors.
    private static func check(_ status: OSStatus) throws {
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

/// A framework failed to provide an expected media object.
enum RendererError: Error {
    case allocation
    case logoUnavailable
}
