//
//  VideoSubtitle.swift
//  FaceNow
//

import AppKit
import CoreText

/// Renders one caption into a bottom-aligned strip shared by preview and camera output.
enum VideoSubtitle {

    /// The fraction of the video height reserved for the transparent strip.
    static let heightRatio: CGFloat = 64.0 / 360.0

    /// Draws up to two centered lines with a translucent background in output pixel coordinates.
    static func makeImage(
        text: String,
        format: VideoFormat
    ) -> CGImage? {
        let caption = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !caption.isEmpty else { return nil }
        let width = CGFloat(format.width)
        let height = CGFloat(format.height)
        let scale = min(width / 640, height / 360)
        let font = NSFont.systemFont(ofSize: 16 * scale, weight: .semibold)
        let horizontalPadding = 10 * scale
        let verticalPadding = 4 * scale
        let textWidth = width * 0.84 - 2 * horizontalPadding
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ]
        let attributedText = NSAttributedString(string: caption, attributes: attributes)
        let typesetter = CTTypesetterCreateWithAttributedString(attributedText)
        let firstLength = CTTypesetterSuggestLineBreak(typesetter, 0, Double(textWidth))
        guard firstLength > 0 else { return nil }
        var lines = [CTTypesetterCreateLine(typesetter, CFRange(location: 0, length: firstLength))]
        if firstLength < attributedText.length {
            let remaining = attributedText.attributedSubstring(
                from: NSRange(location: firstLength, length: attributedText.length - firstLength)
            )
            let line = CTLineCreateWithAttributedString(remaining)
            let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
            if let fitted = CTLineCreateTruncatedLine(line, Double(textWidth), .end, ellipsis) {
                lines.append(fitted)
            }
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: format.width,
                height: Int(ceil(height * heightRatio)),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        let lineWidths = lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }
        let lineHeight = font.ascender - font.descender + scale
        let backgroundWidth = ceil((lineWidths.max() ?? 0) + 2 * horizontalPadding)
        let background = CGRect(
            x: (width - backgroundWidth) / 2,
            y: 12 * scale,
            width: backgroundWidth,
            height: ceil(CGFloat(lines.count) * lineHeight + 2 * verticalPadding)
        )
        context.addPath(CGPath(roundedRect: background, cornerWidth: 6 * scale, cornerHeight: 6 * scale, transform: nil))
        context.setFillColor(CGColor(gray: 0, alpha: 0.72))
        context.fillPath()
        context.textMatrix = .identity
        for (index, line) in lines.enumerated() {
            context.textPosition = CGPoint(
                x: (width - lineWidths[index]) / 2,
                y: background.maxY - verticalPadding - font.ascender - CGFloat(index) * lineHeight
            )
            CTLineDraw(line, context)
        }
        return context.makeImage()
    }
}
