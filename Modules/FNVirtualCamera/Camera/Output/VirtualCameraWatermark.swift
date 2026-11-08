//
//  VirtualCameraWatermark.swift
//  FaceNow
//

import AppKit
import CoreText
#if canImport(CameraCore)
    import CameraCore
#endif

/// Prepares static product artwork once for the virtual camera's output canvas.
enum VirtualCameraWatermark {

    /// Reports failure to allocate the fixed artwork before the camera transport starts.
    enum RenderingError: Error {
        /// Core Graphics could not allocate or export the cached artwork bitmap.
        case allocation
    }

    /// Draws the product name at top left and the generation badge at top right.
    /// The bitmap uses output pixel coordinates and never reads or modifies a source video frame.
    static func makeImage(
        format: VideoFormat,
        generationCaption: String
    ) throws -> CGImage {
        let context = try bitmapContext(width: format.width, height: format.height)
        let width = CGFloat(format.width)
        let height = CGFloat(format.height)
        let scale = min(width / 640, height / 360)
        let brand = try brandImage(scale: scale)
        let brandBounds = CGRect(
            x: 12 * scale,
            y: height - 12 * scale - CGFloat(brand.height),
            width: CGFloat(brand.width),
            height: CGFloat(brand.height)
        )
        context.interpolationQuality = .none
        context.draw(brand, in: brandBounds)

        let badge = try badgeImage(text: generationCaption, scale: scale)
        let badgeBounds = CGRect(
            x: width - 12 * scale - CGFloat(badge.width),
            y: height - 12 * scale - CGFloat(badge.height),
            width: CGFloat(badge.width),
            height: CGFloat(badge.height)
        )
        context.draw(badge, in: badgeBounds)
        guard let image = context.makeImage() else { throw RenderingError.allocation }
        return image
    }

    /// Rasterizes the brand once for the cached output artwork.
    private static func brandImage(
        scale: CGFloat
    ) throws -> CGImage {
        let brand = line("✦ FaceNow", size: 11 * scale, weight: .semibold, opacity: 0.8)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = Int(ceil(CTLineGetTypographicBounds(brand, &ascent, &descent, nil)))
        let height = Int(ceil(ascent + descent))
        let context = try bitmapContext(width: width, height: height)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: 0, y: descent + (CGFloat(height) - ascent - descent) / 2)
        CTLineDraw(brand, context)
        guard let image = context.makeImage() else { throw RenderingError.allocation }
        return image
    }

    /// Rasterizes the caption and its rounded background as one cached badge.
    private static func badgeImage(
        text: String,
        scale: CGFloat
    ) throws -> CGImage {
        let caption = line(text, size: 10 * scale, weight: .regular, opacity: 0.65)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(caption, &ascent, &descent, &leading))
        let textHeight = ceil(ascent + descent + leading)
        let width = Int(ceil(textWidth + 12 * scale))
        let height = Int(ceil(textHeight + 6 * scale))
        let context = try bitmapContext(width: width, height: height)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.addPath(CGPath(roundedRect: bounds, cornerWidth: 8 * scale, cornerHeight: 8 * scale, transform: nil))
        context.setFillColor(CGColor(gray: 0, alpha: 0.35))
        context.fillPath()
        context.textMatrix = .identity
        context.textPosition = CGPoint(
            x: 6 * scale,
            y: (CGFloat(height) - ascent - descent) / 2 + descent
        )
        CTLineDraw(caption, context)
        guard let image = context.makeImage() else { throw RenderingError.allocation }
        return image
    }

    /// Allocates a transparent, premultiplied sRGB tile for cached product artwork.
    private static func bitmapContext(
        width: Int,
        height: Int
    ) throws -> CGContext {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )
        else { throw RenderingError.allocation }
        return context
    }

    /// Shapes a native system-font line, including fallback glyphs for the supplied caption.
    private static func line(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight,
        opacity: CGFloat
    ) -> CTLine {
        CTLineCreateWithAttributedString(
            NSAttributedString(
                string: text,
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): NSFont.systemFont(
                        ofSize: size,
                        weight: weight
                    ),
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: opacity),
                ]
            )
        )
    }
}
