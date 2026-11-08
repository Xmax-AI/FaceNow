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

    /// Allows more reading time for longer pages and denser writing systems.
    static func readingDuration(
        for page: String,
        language: Locale.Language
    ) -> Duration {
        let charactersPerSecond: Double = switch language.languageCode?.identifier {
        case "zh", "ja": 10
        case "ko": 12
        default: 18
        }
        return .seconds(min(6, max(1.4, Double(page.count) / charactersPerSecond)))
    }

    /// Divides a caption at measured two-line boundaries, preferring a nearby phrase ending.
    static func pages(
        text: String,
        format: VideoFormat
    ) -> [String] {
        let caption = normalized(text)
        guard !caption.isEmpty else { return [] }
        let scale = scale(for: format)
        let width = textWidth(for: format, scale: scale)
        let attributedText = NSAttributedString(string: caption, attributes: [.font: captionFont(scale: scale)])
        let typesetter = CTTypesetterCreateWithAttributedString(attributedText)
        let source = caption as NSString
        var pages: [String] = []
        var start = 0
        while start < source.length {
            let firstEnd = start + lineLength(typesetter, source: source, start: start, width: width)
            var end = firstEnd
            if firstEnd < source.length {
                end += lineLength(typesetter, source: source, start: firstEnd, width: width)
            }
            if end < source.length, end > firstEnd {
                let tailStart = firstEnd + (end - firstEnd) / 2
                let tail = NSRange(location: tailStart, length: end - tailStart)
                let punctuation = source.rangeOfCharacter(
                    from: CharacterSet(charactersIn: ",.!?;:"),
                    options: .backwards,
                    range: tail
                )
                let phraseEnd = NSMaxRange(punctuation)
                if punctuation.location != NSNotFound, source.character(at: phraseEnd) == 0x20 {
                    end = phraseEnd
                }
            }
            pages.append(source.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespaces))
            start = end
            if start < source.length, source.character(at: start) == 0x20 { start += 1 }
        }
        return pages
    }

    /// Draws up to two centered lines with a translucent background in output pixel coordinates.
    static func makeImage(
        text: String,
        format: VideoFormat
    ) -> CGImage? {
        let caption = normalized(text)
        guard !caption.isEmpty else { return nil }
        let width = CGFloat(format.width)
        let height = CGFloat(format.height)
        let scale = scale(for: format)
        let font = captionFont(scale: scale)
        let horizontalPadding = 10 * scale
        let verticalPadding = 4 * scale
        let textWidth = textWidth(for: format, scale: scale)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ]
        let attributedText = NSAttributedString(string: caption, attributes: attributes)
        let typesetter = CTTypesetterCreateWithAttributedString(attributedText)
        let source = caption as NSString
        let firstLength = lineLength(typesetter, source: source, start: 0, width: textWidth)
        var lines = [CTTypesetterCreateLine(typesetter, CFRange(location: 0, length: firstLength))]
        if firstLength < attributedText.length {
            let secondLength = lineLength(typesetter, source: source, start: firstLength, width: textWidth)
            lines.append(CTTypesetterCreateLine(
                typesetter,
                CFRange(location: firstLength, length: secondLength)
            ))
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

    /// Collapses whitespace so wrapping and rendering use the same input.
    private static func normalized(
        _ text: String
    ) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Scales typography and spacing proportionally to the output canvas.
    private static func scale(
        for format: VideoFormat
    ) -> CGFloat {
        min(CGFloat(format.width) / 640, CGFloat(format.height) / 360)
    }

    /// Supplies the same caption typography to layout and drawing.
    private static func captionFont(
        scale: CGFloat
    ) -> NSFont {
        NSFont.systemFont(ofSize: 16 * scale, weight: .semibold)
    }

    /// Reserves horizontal margins and the caption card's insets.
    private static func textWidth(
        for format: VideoFormat,
        scale: CGFloat
    ) -> CGFloat {
        CGFloat(format.width) * 0.84 - 20 * scale
    }

    /// Wraps at words, or at character clusters when a single word exceeds the available width.
    private static func lineLength(
        _ typesetter: CTTypesetter,
        source: NSString,
        start: Int,
        width: CGFloat
    ) -> Int {
        let length = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
        if length > 0 { return length }
        let clusterLength = CTTypesetterSuggestClusterBreak(typesetter, start, Double(width))
        return max(clusterLength, source.rangeOfComposedCharacterSequence(at: start).length)
    }
}
