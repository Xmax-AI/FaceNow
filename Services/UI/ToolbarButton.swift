//
//  ToolbarButton.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import CoreText
import SnapKit

/// Renders toolbar actions and status with the same geometry as the credit capsule.
final class ToolbarButton: Button {

    /// The supported artwork sources for a toolbar icon.
    enum Glyph: Equatable {
        case vector(Icon.Kind)
        case system(String)
    }

    /// The visible content and accessible names for controls without a written title.
    enum Content: Equatable {
        case text(String)
        case labeled(String, icon: Glyph)
        case icon(Glyph, accessibilityLabel: String)
        case avatar(initials: String, accessibilityLabel: String)

        /// Circular controls use the shared toolbar height as their width.
        var isCircular: Bool {
            switch self {
            case .icon, .avatar: true
            case .text, .labeled: false
            }
        }
    }

    /// The interaction expected by the host of the toolbar control.
    enum Role {
        case action
        case toggle
        case menu
        case status
    }

    /// The color treatment, independent of the control's contents and dimensions.
    enum Tone {
        case neutral
        case accent
        case warm
        case danger
        case filledAccent
        case softAccent
    }

    /// Updates the contents and their intrinsic width without replacing the button.
    var content: Content {
        didSet {
            if content != oldValue { applyContent() }
        }
    }

    /// Selects the role once so disclosure and status behavior remain stable.
    let role: Role

    /// Updates the color treatment, for example when the credit balance runs low.
    var tone: Tone {
        didSet {
            if tone != oldValue { applyTone() }
        }
    }

    /// Highlights a toggle while leaving the business state in the caller.
    var isSelected: Bool {
        get { selected }
        set { selected = newValue }
    }

    /// Replaces the icon with a progress indicator while retaining the caller's enablement.
    var isLoading: Bool {
        get { loading }
        set {
            if loading != newValue { loading = newValue }
        }
    }

    /// Retains the circular width constraint for content updates.
    private var circleWidth: Constraint?

    /// The original credit icon defines the common maximum painted dimension.
    private static let creditIconSlot: CGFloat = 15
    private static let creditIconBounds = Icon.visibleBounds(for: .lightning)

    /// Uses the original credit capsule's trailing inset at both outer edges.
    private static let contentInset = ToolbarControlMetrics.trailingPadding

    /// Creates a toolbar control whose layout is determined by its content and role.
    init(
        content: Content,
        role: Role = .action,
        tone: Tone = .neutral,
        onClick: (() -> Void)? = nil
    ) {
        self.content = content
        self.role = role
        self.tone = tone
        super.init(action: onClick)
        configureForToolbar(weight: .medium)
        passive = role == .status
        isEnabled = role != .status
        if role == .status { setAccessibilityRole(.staticText) }
        loadingIconSize = Self.creditIconSlot
        circleWidth = snp.prepareConstraints { make in
            make.width.equalTo(snp.height)
        }.first
        applyContent()
        applyTone()
    }

    /// Storyboard decoding is unsupported for this programmatic control.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Provides a complete, single-line size to parents that use intrinsic layout.
    override var intrinsicContentSize: NSSize {
        let height = ToolbarControlMetrics.compactHeight
        return NSSize(width: preferredWidth(controlHeight: height), height: height)
    }

    /// Measures circles using the same row height that their constraints follow.
    func preferredWidth(
        controlHeight: CGFloat
    ) -> CGFloat {
        content.isCircular ? max(0, controlHeight) : preferredWidth
    }

    /// Draws the complete label at its natural origin after measuring it for layout.
    override func drawTitle(
        in rect: NSRect,
        color: NSColor
    ) {
        guard !title.isEmpty else { return }
        var attributes = titleAttributes
        attributes[.foregroundColor] = color
        let label = title as NSString
        let height = label.size(withAttributes: attributes).height
        label.draw(
            at: NSPoint(x: rect.minX, y: rect.midY - height / 2),
            withAttributes: attributes
        )
    }

    /// Aligns the painted leading edge and moves the icon and title together.
    override func alignedContentOriginX(
        _ x: CGFloat
    ) -> CGFloat {
        guard case .labeled = content else { return x }
        let inkOffset = Self.contentInset - leadingPadding
        return pixelAlignedX(x + inkOffset) - inkOffset
    }

    /// Aligns the disclosure to the display's pixel grid within the centered content group.
    override func disclosureCenterX(
        after titleRect: NSRect
    ) -> CGFloat {
        let centerX = titleRect.maxX + trailingPadding - chevronTrailingPadding - ToolbarControlMetrics.disclosureWidth / 2
        // Each 45-degree stroke extends beyond its endpoint by the horizontal projection of half its width.
        let strokeOverhang = ToolbarControlMetrics.disclosureStrokeWidth / (2 * sqrt(2.0))
        return pixelAlignedX(centerX) + strokeOverhang
    }

    /// Rounds a drawing position in backing pixels without changing the control's measured width.
    private func pixelAlignedX(
        _ x: CGFloat
    ) -> CGFloat {
        guard let context = NSGraphicsContext.current?.cgContext else { return x }
        var pixel = context.convertToDeviceSpace(CGPoint(x: x, y: bounds.midY))
        pixel.x.round()
        return context.convertToUserSpace(pixel).x
    }

    /// Uses the same font and tracking when measuring and drawing the title.
    private var titleAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font ?? .systemFont(ofSize: ToolbarControlMetrics.fontSize, weight: .medium),
            .kern: tracking,
        ]
    }

    /// Applies native labels, disclosure, and the geometry common to all toolbar controls.
    private func applyContent() {
        let glyph: Glyph?
        switch content {
        case let .text(text):
            title = text
            glyph = nil
            setAccessibilityLabel(text)
        case let .labeled(text, artwork):
            title = text
            glyph = artwork
            setAccessibilityLabel(text)
        case let .icon(artwork, label):
            title = ""
            glyph = artwork
            setAccessibilityLabel(label)
        case let .avatar(initials, label):
            title = initials
            glyph = initials.isEmpty ? .system("person.fill") : nil
            setAccessibilityLabel(label)
        }

        let circular = content.isCircular
        if circular {
            circleWidth?.activate()
        } else {
            circleWidth?.deactivate()
        }
        chevron = role == .menu && !circular
        chevronTrailingPadding = Self.contentInset
        leadingPadding = circular ? 0 : Self.contentInset
        trailingPadding = chevron ? ToolbarControlMetrics.disclosurePadding : leadingPadding
        alignment = .center
        centersSymbolVisually = circular
        iconVerticalOffset = 0
        iconSize = Self.creditIconSlot
        iconSpacing = ToolbarControlMetrics.contentSpacing
        applyGlyph(glyph, circular: circular)
        if case .labeled = content, !title.isEmpty {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: title, attributes: titleAttributes))
            let ink = CTLineGetImageBounds(line, nil)
            if !ink.isEmpty {
                // Account for unpainted title space while keeping the title's natural drawing width.
                let advance = (title as NSString).size(withAttributes: titleAttributes).width
                iconSpacing -= ink.minX
                trailingPadding -= advance - ink.maxX
            }
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    /// Fits the painted artwork to the reference icon size without stretching its proportions.
    private func applyGlyph(
        _ glyph: Glyph?,
        circular: Bool
    ) {
        let bounds: CGRect?
        switch glyph {
        case let .vector(kind):
            icon = kind
            symbolName = nil
            bounds = Icon.visibleBounds(for: kind)
        case let .system(name):
            icon = nil
            symbolName = name
            bounds = Self.visibleSymbolBounds(named: name)
        case nil:
            icon = nil
            symbolName = nil
            bounds = nil
        }
        guard let bounds, !bounds.isEmpty else { return }
        let reference = Self.creditIconBounds
        let referenceSize = max(reference.width, reference.height) * Self.creditIconSlot
        iconSize = referenceSize / max(bounds.width, bounds.height)
        guard !circular else { return }
        leadingPadding -= bounds.minX * iconSize
        iconSpacing = ToolbarControlMetrics.contentSpacing - (1 - bounds.maxX) * iconSize
        iconVerticalOffset = (0.5 - bounds.midY) * iconSize
    }

    /// Maps semantic tones onto the shared button surface and motion.
    private func applyTone() {
        switch tone {
        case .neutral: style = .pill
        case .accent: style = .statistics
        case .warm: style = .interpolation
        case .danger: style = .destructive
        case .filledAccent: style = .primary
        case .softAccent: style = .plain
        }
        let tinted = tone == .softAccent
        foregroundColor = tinted ? Palette.accent : nil
        restingBackgroundColor = tinted ? Palette.accent.withAlphaComponent(0.12) : nil
        hoverBackgroundColor = tinted ? Palette.accent.withAlphaComponent(0.18) : nil
        showsShadow = !tinted
    }
}
