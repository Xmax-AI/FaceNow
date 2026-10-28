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
import SnapKit

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

    /// An optional compact corner radius; nil preserves the role's original capsule shape.
    var cornerRadius: CGFloat? { didSet { needsDisplay = true } }

    /// Whether the control's current visual role may draw a shadow.
    var showsShadow = true { didSet { needsDisplay = true } }

    /// Scales the shadow's opacity, blur radius, and offset for a more restrained appearance.
    var shadowScale: CGFloat = 1 { didSet { needsDisplay = true } }

    /// An explicit foreground override for a specialized control.
    var foregroundColor: NSColor? { didSet { needsDisplay = true } }

    /// An optional hover fill for plain actions, using the shared appearance transition.
    var hoverBackgroundColor: NSColor? { didSet { needsDisplay = true } }

    /// An optional resting fill for plain actions, using the shared appearance transition.
    var restingBackgroundColor: NSColor? { didSet { needsDisplay = true } }

    /// Whether an activity ring replaces the control's glyph.
    var loading = false { didSet { updateLoading() } }

    /// Whether the control presents information without invoking an action.
    var passive = false { didSet { updateOpacity() } }

    /// The host-selected opacity for a disabled control without an active loading indicator.
    var disabledOpacity: CGFloat = 0.5 { didSet { updateOpacity() } }

    /// The host-selected opacity while the activity indicator is visible.
    var loadingOpacity: CGFloat = 1 { didSet { updateOpacity() } }

    /// The action invoked when the user activates this control.
    var onClick: (() -> Void)?

    /// Reports pointer entry and exit without exposing the button's drawing state.
    var onHoverChanged: ((Bool) -> Void)?

    /// Whether the pointer is currently inside the control.
    private var hovered = false

    /// The current visible-bounds tracking area.
    private var hoverArea: NSTrackingArea?

    /// The appearance visible when the latest interaction transition began.
    private var transitionStart: ButtonVisualState?

    /// The latest destination; repeated state refreshes do not restart its animation.
    private var transitionTarget: ButtonVisualState?

    /// Native animation updates the custom drawing without replacing the button or its content.
    @objc dynamic private var appearanceProgress: CGFloat = 1 {
        didSet { needsDisplay = true }
    }

    /// Supplies native interpolation for the custom-drawn control appearance.
    override class func defaultAnimation(
        forKey key: NSAnimatablePropertyKey
    ) -> Any? {
        if key == "appearanceProgress" { return CABasicAnimation() }
        return super.defaultAnimation(forKey: key)
    }

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
            updateOpacity()
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
        alignment = .center
        font = Typography.font(size: 13)
        if style == .plain {
            leadingPadding = 0
            trailingPadding = 0
        }
        target = self
        self.action = #selector(invoke)
        wantsLayer = true
        addSubview(spinner)
        spinner.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.centerY.equalToSuperview()
            make.size.equalTo(iconSize)
        }
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
        onHoverChanged?(true)
    }

    /// Clears hover presentation when the pointer leaves the control.
    override func mouseExited(
        with event: NSEvent
    ) {
        hovered = false
        needsDisplay = true
        onHoverChanged?(false)
    }

    /// The effective foreground color for the current role, selection, and pointer state.
    private var foreground: NSColor {
        if let foregroundColor { return foregroundColor }
        if style == .primary { return .white }
        if style == .destructive { return Palette.destructive }
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
        updateOpacity()
        needsDisplay = true
        needsLayout = true
    }

    /// Blends availability while applying the native interaction state immediately.
    private func updateOpacity() {
        ControlMotion.setOpacity(
            loading ? min(1, max(0, loadingOpacity)) : isEnabled || passive ? 1 : min(1, max(0, disabledOpacity)),
            on: self
        )
        needsDisplay = true
    }

    /// Retargets colors and shadows from the last visible appearance, including rapid reversals.
    private func visualState(
        for target: ButtonVisualState
    ) -> ButtonVisualState {
        if transitionTarget != target {
            let visible =
                transitionStart?.blended(
                    toward: transitionTarget ?? target,
                    progress: appearanceProgress
                ) ?? target
            let animated = transitionTarget != nil && ControlMotion.isAnimated(in: self)
            transitionStart = visible
            transitionTarget = target
            appearanceProgress = animated ? 0 : 1
            if animated {
                ControlMotion.animate(in: self) {
                    animator().appearanceProgress = 1
                }
            }
        }
        return transitionStart?.blended(
            toward: target,
            progress: appearanceProgress
        ) ?? target
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
        let x: CGFloat
        switch alignment {
        case .left:
            x = leadingPadding
        case .right:
            x = bounds.width - trailingPadding - total
        default:
            x = leadingPadding + (bounds.width - leadingPadding - trailingPadding - total) / 2
        }
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
        let iconRect = contentFrames().0
        spinner.snp.updateConstraints { make in
            make.leading.equalToSuperview().offset(iconRect.minX)
            make.size.equalTo(iconSize)
        }
        super.layout()
    }

    /// Draws the button's current background, border, shadow, icon, and title.
    override func draw(
        _ dirtyRect: NSRect
    ) {
        let rect = bounds.insetBy(
            dx: backgroundInset + 0.5,
            dy: backgroundInset + 0.5
        )
        let radius = min(rect.height / 2, max(0, cornerRadius ?? rect.height / 2))
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: radius,
            yRadius: radius
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
            let fill = restingBackgroundColor ?? .clear
            top = hot ? hoverBackgroundColor ?? fill : fill
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
        let outlined =
            style == .pill || style == .volume || style == .destructive
            || (!selected && (style == .statistics || style == .interpolation))
        let flat =
            style == .plain || (style == .tab && !selected)
            || (selected && (style == .statistics || style == .interpolation))
        let visual = visualState(
            for: ButtonVisualState(
                top: top,
                bottom: bottom,
                border: border,
                foreground: foreground,
                highlightOpacity: outlined ? 0.6 : 0,
                shadowColor: style == .primary ? Palette.accent : .black,
                shadowOpacity: shadowScale
                    * (!showsShadow || flat ? 0 : style == .primary ? 0.35 : style == .tab ? 0.1 : hot ? 0.08 : 0.05),
                shadowRadius: shadowScale * (style == .primary ? 15 : style == .tab ? 4 : hot ? 8 : 6),
                shadowOffset: shadowScale * (style == .primary ? 10 : style == .tab ? 2 : hot ? 6 : 4)
            )
        )
        NSGradient(
            starting: visual.top,
            ending: visual.bottom
        )?.draw(
            in: path,
            angle: 90
        )
        if visual.highlightOpacity > 0 {
            let highlight = NSBezierPath(
                roundedRect: rect.insetBy(
                    dx: 1,
                    dy: 1
                ),
                xRadius: max(0, radius - 1),
                yRadius: max(0, radius - 1)
            )
            NSColor.white.withAlphaComponent(visual.highlightOpacity).setStroke()
            highlight.lineWidth = 1
            highlight.stroke()
        }
        visual.border.setStroke()
        path.lineWidth = 1
        path.stroke()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.shadowColor = visual.shadowColor.cgColor
        layer?.shadowOpacity = Float(visual.shadowOpacity)
        layer?.shadowRadius = visual.shadowRadius
        layer?.shadowOffset = CGSize(
            width: 0,
            height: visual.shadowOffset
        )
        layer?.shadowPath = CGPath(
            roundedRect: rect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
        CATransaction.commit()
        let (iconRect, textRect) = contentFrames()
        if let icon, !loading {
            Icon.draw(
                icon,
                in: iconRect,
                color: visual.foreground
            )
        }
        if let symbolName, !loading {
            NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: nil
            )?
            .withSymbolConfiguration(.init(paletteColors: [visual.foreground]))?
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
            .font: font ?? Typography.font(size: 13), .foregroundColor: visual.foreground, .paragraphStyle: paragraph,
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

/// Captures interpolatable colors and shadow metrics independently of native interaction state.
private struct ButtonVisualState: Equatable {

    /// The upper gradient color.
    var top: NSColor

    /// The lower gradient color.
    var bottom: NSColor

    /// The outer outline color.
    var border: NSColor

    /// The shared title and icon color.
    var foreground: NSColor

    /// The inner highlight's opacity.
    var highlightOpacity: CGFloat

    /// The shadow's tint.
    var shadowColor: NSColor

    /// The shadow's opacity.
    var shadowOpacity: CGFloat

    /// The shadow's blur radius, in points.
    var shadowRadius: CGFloat

    /// The shadow's vertical offset, in points.
    var shadowOffset: CGFloat

    /// Interpolates the complete appearance at the native animation's current progress.
    func blended(
        toward target: ButtonVisualState,
        progress: CGFloat
    ) -> ButtonVisualState {
        let amount = min(1, max(0, progress))
        return ButtonVisualState(
            top: top.blended(withFraction: amount, of: target.top) ?? target.top,
            bottom: bottom.blended(withFraction: amount, of: target.bottom) ?? target.bottom,
            border: border.blended(withFraction: amount, of: target.border) ?? target.border,
            foreground: foreground.blended(withFraction: amount, of: target.foreground) ?? target.foreground,
            highlightOpacity: highlightOpacity + (target.highlightOpacity - highlightOpacity) * amount,
            shadowColor: shadowColor.blended(withFraction: amount, of: target.shadowColor) ?? target.shadowColor,
            shadowOpacity: shadowOpacity + (target.shadowOpacity - shadowOpacity) * amount,
            shadowRadius: shadowRadius + (target.shadowRadius - shadowRadius) * amount,
            shadowOffset: shadowOffset + (target.shadowOffset - shadowOffset) * amount
        )
    }
}
