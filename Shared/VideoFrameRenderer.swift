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
import CoreText
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
        waitingImage = Self.makeWaitingImage()
    }

    /// Scales the input to fit, adding opaque black bars where needed.
    func normalize(_ pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = Self.fittedRect(width: image.extent.width, height: image.extent.height)
        let fitted = image.transformed(by: CGAffineTransform(
            scaleX: rect.width / image.extent.width, y: rect.height / image.extent.height
        )).transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return try render(fitted.composited(over: CIImage(color: .black).cropped(to: bounds)))
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

    /// Wraps a frame using the host clock rather than the remote RTC timebase.
    func sampleBuffer(_ pixelBuffer: CVPixelBuffer, at time: CMTime) throws -> CMSampleBuffer {
        var description: CMVideoFormatDescription?
        try Self.check(CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &description
        ))
        guard let description else { throw RendererError.allocation }
        var timing = CMSampleTimingInfo(
            duration: CameraConfiguration.frameDuration, presentationTimeStamp: time, decodeTimeStamp: .invalid
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

    /// Calculates an aspect-preserving centered output rectangle.
    static func fittedRect(width: CGFloat, height: CGFloat) -> CGRect {
        guard width > 0, height > 0 else { return .zero }
        let scale = min(CGFloat(CameraConfiguration.width) / width, CGFloat(CameraConfiguration.height) / height)
        let size = CGSize(width: width * scale, height: height * scale)
        return CGRect(x: (CGFloat(CameraConfiguration.width) - size.width) / 2,
                      y: (CGFloat(CameraConfiguration.height) - size.height) / 2,
                      width: size.width, height: size.height)
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

    /// Builds a horizontally mirrored offline card once for mirrored meeting self-views.
    private static func makeWaitingImage() -> CIImage {
        let width = CameraConfiguration.width
        let height = CameraConfiguration.height
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (text, size, y) in [("Xmax Camera", 44.0, 370.0), ("Waiting for generation", 24.0, 320.0)] {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("HelveticaNeue" as CFString, size, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.9, alpha: 1)
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
            context.textPosition = CGPoint(x: (Double(width) - lineWidth) / 2, y: y)
            CTLineDraw(line, context)
        }
        return CIImage(cgImage: context.makeImage()!).transformed(by: CGAffineTransform(
            a: -1, b: 0, c: 0, d: 1, tx: CGFloat(width), ty: 0
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
}
