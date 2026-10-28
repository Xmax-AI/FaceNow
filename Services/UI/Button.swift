//
//  Button.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit

/// Native buttons retain their identity, loading animation, keyboard focus, and target action.
final class Button: NSButton {

    /// The visual roles supported by the shared native button.
    enum Appearance {

        /// A standard rounded setup or information control.
        case pill

        /// An emphasized action using the product accent color.
        case primary

        /// A stop or removal action using a red foreground and outline.
        case destructive

        /// A compact diagnostic-visibility control with a selected state.
        case statistics

        /// A compact interpolation control with an emphasized enabled state.
        case interpolation

        /// A compact remote-playback volume control.
        case volume

        /// A selectable generation-mode tab.
        case tab

        /// An unbordered footer or text action.
        case plain

        /// A compact filled dismissal action with a configurable hit area.
        case dismiss
    }

    /// The visual role used when drawing the native button.
    var style = Appearance.pill { didSet { needsDisplay = true } }

    /// Whether the control displays its selected appearance.
    var selected = false { didSet { if selected != oldValue { needsDisplay = true } } }

    /// The optional custom vector glyph placed before the title.
    var icon: Icon.Kind? { didSet { needsDisplay = true } }

    /// The optional system symbol displayed instead of a custom glyph.
    var symbolName: String? { didSet { needsDisplay = true } }

    /// Whether a disclosure chevron is drawn at the trailing edge.
    var chevron = false

    /// The leading content inset, in points.
    var leadingPadding: CGFloat = 14

    /// The trailing content inset, in points.
    var trailingPadding: CGFloat = 14

    /// The square glyph size, in points.
    var iconSize: CGFloat = 18

    /// The gap between an icon and a nonempty title, in points.
    var iconSpacing: CGFloat = 8

    /// The title's character spacing, in points.
    var tracking: CGFloat = 0

    /// Shrinks the visible background without reducing the control's hit area.
    var backgroundInset: CGFloat = 0 { didSet { needsDisplay = true } }

    /// Whether the control's current visual role may draw a shadow.
    var showsShadow = true { didSet { needsDisplay = true } }

    /// An explicit foreground override for a specialized control.
    var foregroundColor: NSColor?

    /// Whether an activity ring replaces the control's glyph.
    var loading = false { didSet { updateLoading() } }

    /// Whether the control presents information without invoking an action.
    var passive = false

    /// The action invoked when the user activates this control.
    var onClick: (() -> Void)?

    /// Whether the pointer is currently inside the control.
    private var hovered = false

    /// The current visible-bounds tracking area.
    private var hoverArea: NSTrackingArea?

    /// The lazily created loading ring retained across state updates.
    private lazy var spinner: Spinner = {
        let view = Spinner()
        return view
    }()

    /// Whether layout coordinates start at the top-left corner.
    override var isFlipped: Bool { true }

    /// The native enabled state whose appearance also accounts for loading and passive presentation.
    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled || loading || passive ? 1 : 0.5
            needsDisplay = true
        }
    }

    /// Creates a persistent native button with its visual role and optional action.
    init(
        _ title: String = "",
        icon: Icon.Kind? = nil,
        style: Appearance = .pill,
        action: (() -> Void)? = nil
    ) {
        super.init(frame: .zero)
        self.title = title
        self.icon = icon
        self.style = style
        self.onClick = action
        isBordered = false
        setButtonType(.momentaryPushIn)
        font = Typography.font(size: 13)
        if style == .plain {
            leadingPadding = 0
            trailingPadding = 0
        }
        target = self
        self.action = #selector(invoke)
        wantsLayer = true
        addSubview(spinner)
        spinner.isHidden = true
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Invokes the enabled control action without replacing its native identity.
    @objc private func invoke() { if !passive { onClick?() } }

    /// Replaces the hover-tracking area for the current visible bounds.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        hoverArea = area
    }

    /// Marks the control as hovered and requests an appearance update.
    override func mouseEntered(
        with event: NSEvent
    ) {
        hovered = true
        needsDisplay = true
    }

    /// Clears hover presentation when the pointer leaves the control.
    override func mouseExited(
        with event: NSEvent
    ) {
        hovered = false
        needsDisplay = true
    }

    /// The effective foreground color for the current role, selection, and pointer state.
    private var foreground: NSColor {
        if let foregroundColor { return foregroundColor }
        if style == .primary { return .white }
        if style == .destructive {
            return NSColor(
                srgbRed: 220 / 255,
                green: 38 / 255,
                blue: 38 / 255,
                alpha: 1
            )
        }
        if selected && style == .statistics { return Palette.accent }
        if selected && style == .interpolation {
            return NSColor(
                srgbRed: 169 / 255,
                green: 102 / 255,
                blue: 8 / 255,
                alpha: 1
            )
        }
        if style == .statistics || style == .interpolation || style == .volume {
            return selected || (hovered && isEnabled)
                ? Palette.text
                : NSColor(
                    srgbRed: 139 / 255,
                    green: 145 / 255,
                    blue: 157 / 255,
                    alpha: 1
                )
        }
        if passive || style == .plain || (style == .tab && !selected && !hovered) { return Palette.secondary }
        return Palette.text
    }

    /// Updates the retained activity ring and schedules presentation after a loading change.
    private func updateLoading() {
        spinner.setSpinning(
            loading,
            color: foreground
        )
        alphaValue = isEnabled || loading || passive ? 1 : 0.5
        needsDisplay = true
        needsLayout = true
    }

    /// Measures the label and icon with the Web component's explicit padding.
    var preferredWidth: CGFloat {
        ceil(
            Typography.size(
                title,
                font: font!,
                tracking: tracking
            ).width + ((icon != nil || symbolName != nil || loading) ? iconSize + (title.isEmpty ? 0 : iconSpacing) : 0)
                + leadingPadding + trailingPadding
        )
    }

    /// Measures icon and title frames within the configured content insets.
    private func contentFrames() -> (NSRect, NSRect) {
        let hasIcon = icon != nil || symbolName != nil || loading
        let iconWidth = hasIcon ? iconSize + (title.isEmpty ? 0 : iconSpacing) : 0
        let available = max(0, bounds.width - leadingPadding - trailingPadding - iconWidth)
        let textWidth = min(
            available,
            Typography.size(
                title,
                font: font!,
                tracking: tracking
            ).width
        )
        let total = iconWidth + textWidth
        let x = leadingPadding + (bounds.width - leadingPadding - trailingPadding - total) / 2
        return (
            NSRect(
                x: x,
                y: (bounds.height - iconSize) / 2,
                width: iconSize,
                height: iconSize
            ),
            NSRect(
                x: x + iconWidth,
                y: 0,
                width: textWidth,
                height: bounds.height
            )
        )
    }

    /// Places the retained activity ring at the measured icon position.
    override func layout() {
        super.layout()
        spinner.frame = contentFrames().0
    }

    /// Draws the button's current background, border, shadow, icon, and title.
    override func draw(
        _ dirtyRect: NSRect
    ) {
        let rect = bounds.insetBy(
            dx: backgroundInset + 0.5,
            dy: backgroundInset + 0.5
        )
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: rect.height / 2,
            yRadius: rect.height / 2
        )
        let hot = hovered && isEnabled && !passive
        var top = NSColor.white
        var bottom = NSColor(
            srgbRed: 243 / 255,
            green: 244 / 255,
            blue: 246 / 255,
            alpha: 1
        )
        var border =
            hot
            ? NSColor(
                srgbRed: 201 / 255,
                green: 206 / 255,
                blue: 214 / 255,
                alpha: 1
            )
            : NSColor(
                srgbRed: 226 / 255,
                green: 229 / 255,
                blue: 234 / 255,
                alpha: 1
            )
        switch style {
        case .primary:
            top = hot ? Palette.accentHover : Palette.accent
            bottom = top
            border = .clear
        case .dismiss:
            let gray: CGFloat = hot ? 0.32 : 0.24
            top = NSColor(
                srgbRed: gray,
                green: gray,
                blue: gray,
                alpha: 1
            )
            bottom = top
            border = .clear
        case .destructive:
            bottom = NSColor(
                srgbRed: 253 / 255,
                green: hot ? 232 / 255 : 242 / 255,
                blue: hot ? 232 / 255 : 242 / 255,
                alpha: 1
            )
            border = foreground.withAlphaComponent(hot ? 0.5 : 0.28)
        case .statistics where selected:
            top = NSColor(
                srgbRed: 238 / 255,
                green: 241 / 255,
                blue: 1,
                alpha: 1
            )
            bottom = top

            border = NSColor(
                srgbRed: 215 / 255,
                green: 221 / 255,
                blue: 251 / 255,
                alpha: 1
            )
        case .interpolation where selected:
            top = NSColor(
                srgbRed: 1,
                green: 250 / 255,
                blue: 240 / 255,
                alpha: 1
            )
            bottom = NSColor(
                srgbRed: 1,
                green: 240 / 255,
                blue: 202 / 255,
                alpha: 1
            )
            border = NSColor(
                srgbRed: 240 / 255,
                green: 207 / 255,
                blue: 136 / 255,
                alpha: 1
            )
        case .tab:
            top = selected ? .white : .white.withAlphaComponent(hot ? 0.65 : 0)
            bottom = top
            border = .clear
        case .plain:
            top = .white.withAlphaComponent(0)
            bottom = top
            border = .clear
        default: break
        }
        if isHighlighted {
            bottom =
                bottom.blended(
                    withFraction: 0.06,
                    of: .black
                ) ?? bottom
        }
        NSGradient(
            starting: top,
            ending: bottom
        )?.draw(
            in: path,
            angle: 90
        )
        if style == .pill || style == .volume || style == .destructive
            || (!selected && (style == .statistics || style == .interpolation))
        {
            let highlight = NSBezierPath(
                roundedRect: rect.insetBy(
                    dx: 1,
                    dy: 1
                ),
                xRadius: rect.height / 2 - 1,
                yRadius: rect.height / 2 - 1
            )
            NSColor.white.withAlphaComponent(0.6).setStroke()
            highlight.lineWidth = 1
            highlight.stroke()
        }
        border.setStroke()
        path.lineWidth = 1
        path.stroke()
        layer?.shadowColor = (style == .primary ? Palette.accent : NSColor.black).cgColor
        let flat =
            style == .plain || (style == .tab && !selected)
            || (selected && (style == .statistics || style == .interpolation))
        layer?.shadowOpacity =
            !showsShadow || flat ? 0 : style == .primary ? 0.35 : style == .tab ? 0.1 : hot ? 0.08 : 0.05
        layer?.shadowRadius = style == .primary ? 15 : style == .tab ? 4 : hot ? 8 : 6
        layer?.shadowOffset = CGSize(
            width: 0,
            height: style == .primary ? 10 : style == .tab ? 2 : hot ? 6 : 4
        )
        layer?.shadowPath = CGPath(
            roundedRect: rect,
            cornerWidth: rect.height / 2,
            cornerHeight: rect.height / 2,
            transform: nil
        )
        let (iconRect, textRect) = contentFrames()
        if let icon, !loading {
            Icon.draw(
                icon,
                in: iconRect,
                color: foreground
            )
        }
        if let symbolName, !loading {
            NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: nil
            )?
            .withSymbolConfiguration(.init(paletteColors: [foreground]))?
            .draw(
                in: iconRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? Typography.font(size: 13), .foregroundColor: foreground, .paragraphStyle: paragraph,
            .kern: tracking,
        ]
        let height = (title as NSString).size(withAttributes: attributes).height
        (title as NSString).draw(
            in: NSRect(
                x: textRect.minX,
                y: (bounds.height - height) / 2,
                width: textRect.width,
                height: height
            ),
            withAttributes: attributes
        )
        if chevron {
            let arrow = NSBezierPath()
            let x = bounds.width - 20, y = bounds.midY
            arrow.move(
                to: NSPoint(
                    x: x - 3,
                    y: y - 1.5
                )
            )

            arrow.line(
                to: NSPoint(
                    x: x,
                    y: y + 1.5
                )
            )

            arrow.line(
                to: NSPoint(
                    x: x + 3,
                    y: y - 1.5
                )
            )
            Palette.secondary.setStroke()
            arrow.lineWidth = 1
            arrow.stroke()
        }
    }
}
