//
//  Theme.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import CoreText

/// Shared light surfaces and blue accents for native product controls.
enum Palette {

    /// The primary foreground color used by product labels and controls.
    static let text = NSColor(
        srgbRed: 0.067,
        green: 0.075,
        blue: 0.094,
        alpha: 1
    )

    /// The secondary foreground color used by hints and supporting labels.
    static let secondary = NSColor(
        srgbRed: 0.42,
        green: 0.45,
        blue: 0.50,
        alpha: 1
    )

    /// The neutral surface color used by editors and reference placeholders.
    static let surface = NSColor(
        srgbRed: 0.969,
        green: 0.973,
        blue: 0.980,
        alpha: 1
    )

    /// The lighter idle background used by native login inputs.
    static let inputSurface = NSColor(
        srgbRed: 0.985,
        green: 0.987,
        blue: 0.990,
        alpha: 1
    )

    /// The neutral border color used by input containers and upload controls.
    static let border = NSColor(
        srgbRed: 0.898,
        green: 0.906,
        blue: 0.922,
        alpha: 1
    )

    /// The product accent shared by primary actions, links, and focus indicators.
    static let accent = NSColor(
        srgbRed: 47 / 255,
        green: 70 / 255,
        blue: 226 / 255,
        alpha: 1
    )

    /// The deeper blue used while a primary action is hovered.
    static let accentHover = NSColor(
        srgbRed: 36 / 255,
        green: 56 / 255,
        blue: 196 / 255,
        alpha: 1
    )

    /// The shared red foreground for stop actions and low-credit warnings.
    static let destructive = NSColor(
        srgbRed: 220 / 255,
        green: 38 / 255,
        blue: 38 / 255,
        alpha: 1
    )

    /// The green foreground for confirmed available states.
    static let success = NSColor(
        srgbRed: 21 / 255,
        green: 128 / 255,
        blue: 61 / 255,
        alpha: 1
    )
}

/// Shared appearance metrics for home and generation toolbar buttons.
enum ToolbarControlMetrics {

    /// The subtle resting outline shared by neutral toolbar controls.
    static let border = NSColor(
        srgbRed: 235 / 255,
        green: 238 / 255,
        blue: 242 / 255,
        alpha: 1
    )

    /// The stronger outline reserved for the toolbar control under the pointer.
    static let hoverBorder = NSColor(
        srgbRed: 201 / 255,
        green: 206 / 255,
        blue: 214 / 255,
        alpha: 1
    )

    /// The gap between adjacent controls, including account and camera group boundaries.
    static let spacing: CGFloat = 12

    /// The title and avatar text size shared by the toolbar controls.
    static let fontSize: CGFloat = 13

    /// The fixed height shared by home and generation toolbar controls.
    static let compactHeight: CGFloat = 36

    /// The common icon slot size.
    static let iconSize: CGFloat = 16

    /// The gap between an icon and its title.
    static let contentSpacing: CGFloat = 4

    /// The shared leading content inset for a pill.
    static let leadingPadding: CGFloat = 12

    /// The trailing content inset for a pill with an icon; text-only pills use the leading inset on both sides.
    static let trailingPadding: CGFloat = 14

    /// The width reserved for a disclosure chevron.
    static let disclosureWidth: CGFloat = 6

    /// The title-to-chevron gap, independent of icon-to-title spacing.
    static let disclosureSpacing: CGFloat = 8

    /// The trailing inset including the title-to-chevron gap and chevron itself.
    static let disclosurePadding = trailingPadding + disclosureSpacing + disclosureWidth

    /// The common responsive height used for measuring and constraining toolbar controls.
    static func height(
        viewportWidth: CGFloat
    ) -> CGFloat {
        min(48, max(35, viewportWidth * 0.0055 + 26))
    }
}

/// Uses the bundled Web font for native labels and controls.
@MainActor
enum Typography {

    /// The bundled variable font shared by AppKit and application-owned web content.
    private static let fontURL = Bundle.main.url(
        forResource: "DMSans",
        withExtension: "ttf"
    )

    /// Registers the bundled variable font once for the current process.
    private static let registered: Void = {
        if let url = fontURL {
            CTFontManagerRegisterFontsForURL(
                url as CFURL,
                .process,
                nil
            )
        }
    }()

    /// Embeds the bundled font in the application's web wrapper without a remote font request.
    /// Third-party verification frames retain their own presentation and security behavior.
    static let webFontCSS: String = {
        let family = "html,body,button,input,textarea,select{font-family:'DM Sans','PingFang SC',sans-serif}"
        guard let url = fontURL, let data = try? Data(contentsOf: url) else { return family }
        return """
            @font-face{
                font-family:'DM Sans';
                src:url('data:font/ttf;base64,\(data.base64EncodedString())') format('truetype');
                font-weight:100 900;
                font-style:normal;
            }
            \(family)
            """
    }()

    /// Creates the shared variable font with the requested weight and optional aligned numeric runs.
    /// Fonts without tabular-digit support use fixed advances for the entire numeric font run.
    static func font(
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        monospacedDigits: Bool = false
    ) -> NSFont {
        _ = registered
        guard
            let base = NSFont(
                name: "DMSans9pt-Regular",
                size: size
            )
        else {
            return .systemFont(
                ofSize: size,
                weight: weight
            )
        }
        // The bundled font has a variable weight axis; NSFont trait matching leaves it at 400.
        let value = weight == .semibold ? 600 : weight == .medium ? 500 : weight == .bold ? 700 : 400
        var attributes: [CFString: Any] = [
            kCTFontVariationAttribute: [NSNumber(value: 0x77676874): NSNumber(value: value)]
        ]
        if monospacedDigits {
            attributes[kCTFontFeatureSettingsAttribute] = [
                [
                    kCTFontFeatureTypeIdentifierKey: kNumberSpacingType,
                    kCTFontFeatureSelectorIdentifierKey: kMonospacedNumbersSelector,
                ]
            ]
        }
        let result = CTFontCreateCopyWithAttributes(
            base,
            size,
            nil,
            CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        )
        guard monospacedDigits else { return result as NSFont }
        return alignedNumericFont(result)
    }

    /// Retains DM Sans glyphs while stabilizing numeric runs when tabular digits are unavailable.
    private static func alignedNumericFont(
        _ font: CTFont
    ) -> NSFont {
        let characters = Array("0123456789".utf16)
        var glyphs = [CGGlyph](
            repeating: 0,
            count: characters.count
        )
        guard
            CTFontGetGlyphsForCharacters(
                font,
                characters,
                &glyphs,
                characters.count
            )
        else { return font as NSFont }
        var advances = [CGSize](
            repeating: .zero,
            count: glyphs.count
        )
        CTFontGetAdvancesForGlyphs(
            font,
            .horizontal,
            glyphs,
            &advances,
            glyphs.count
        )
        let widths = advances.map(\.width)
        guard let widest = widths.max(), let narrowest = widths.min(), widest - narrowest > 0.01 else {
            return font as NSFont
        }
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFixedAdvanceAttribute: widest] as CFDictionary)
        return CTFontCreateCopyWithAttributes(
            font,
            CTFontGetSize(font),
            nil,
            descriptor
        ) as NSFont
    }

    /// Aligns ASCII digits while retaining normal DM Sans spacing for units and punctuation.
    static func numericText(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor
    ) -> NSAttributedString {
        let base = font(
            size: size,
            weight: weight
        )
        let numeric = alignedNumericFont(base)
        let result = NSMutableAttributedString(
            string: text,
            attributes: [.font: base, .foregroundColor: color]
        )
        for (index, character) in text.utf16.enumerated() where character >= 48 && character <= 57 {
            result.addAttribute(
                .font,
                value: numeric,
                range: NSRange(
                    location: index,
                    length: 1
                )
            )
        }
        return result
    }

    /// Measures text using the same font and tracking as the drawing controls.
    static func size(
        _ text: String,
        font: NSFont,
        tracking: CGFloat = 0
    ) -> NSSize {
        (text as NSString).size(withAttributes: [.font: font, .kern: tracking])
    }
}
