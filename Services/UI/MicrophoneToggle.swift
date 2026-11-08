//
//  MicrophoneToggle.swift
//  FaceNow
//

import AppKit

/// Matches xlab-react's micToggle, micSwitch and micKnob without NSSwitch's internal margins.
final class MicrophoneToggle: NSButton {

    /// Whether layout coordinates start at the top-left corner.
    override var isFlipped: Bool { true }

    /// The native microphone toggle state reflected by the custom track.
    override var state: NSControl.StateValue { didSet { updateAppearance() } }

    /// The native enabled state controlling the toggle's visual opacity.
    override var isEnabled: Bool {
        didSet {
            ControlMotion.setOpacity(
                isEnabled ? 1 : 0.5,
                on: self
            )
        }
    }

    /// The animatable zero-through-one position of the toggle knob.
    @objc dynamic private var onProgress: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    /// The destination knob position used to avoid duplicate animations.
    private var targetProgress: CGFloat = 0

    /// Supplies the layer animation used when changing the knob position.
    override class func defaultAnimation(
        forKey key: NSAnimatablePropertyKey
    ) -> Any? {
        if key == "onProgress" { return CABasicAnimation() }
        return super.defaultAnimation(forKey: key)
    }

    /// Creates a native full-bounds toggle with the shared microphone appearance.
    init() {
        super.init(frame: .zero)
        title = Localization.string("control.microphone", table: "Common", defaultValue: "Microphone")
        font = Typography.font(size: 13)
        wantsLayer = true
        // Checkbox cells only track their native indicator/title, not the custom track on the right.
        setButtonType(.pushOnPushOff)
        // Keep full-bounds mouse tracking; draw(_:) supplies the Web appearance instead of the native bezel.
        isBordered = true
        target = self
        action = #selector(didToggle)
        setAccessibilityLabel(title)
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// The text, icon, and track size including the toggle's explicit content insets.
    override var intrinsicContentSize: NSSize {
        let text = Typography.size(
            title,
            font: font!
        )
        // CSS padding: 6px 7px 6px 14px; 8px gaps; 1px border.
        return NSSize(
            width: 2 + 14 + 14 + 8 + ceil(text.width) + 8 + 30 + 7,
            height: 2 + 6 + max(18, ceil(text.height)) + 6
        )
    }

    /// Updates custom presentation after the native button cell changes its state.
    @objc private func didToggle() {
        // Native button cells can change their state without invoking our state setter.
        updateAppearance()
        NSAccessibility.post(
            element: self,
            notification: .valueChanged
        )
    }

    /// Animates the knob toward the native state while respecting reduced motion.
    private func updateAppearance() {
        let progress: CGFloat = state == .on ? 1 : 0
        guard progress != targetProgress else { return }
        targetProgress = progress
        ControlMotion.animate(in: self) {
            animator().onProgress = progress
        }
    }

    /// Exposes this control as one accessible toggle.
    override func isAccessibilityElement() -> Bool { true }

    /// Reports the native checkbox role for assistive technologies.
    override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }

    /// Keeps decorative toggle content out of the accessibility hierarchy.
    override func accessibilityChildren() -> [Any]? { [] }

    /// Reports whether microphone capture is selected.
    override func accessibilityValue() -> Any? { NSNumber(value: state == .on) }

    /// Activates the native toggle only while enabled.
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        performClick(nil)
        return true
    }

    /// Draws the microphone label, track, and knob for the current animated state.
    override func draw(
        _ dirtyRect: NSRect
    ) {
        let progress = min(1, max(0, onProgress))
        let foreground = NSColor.white.withAlphaComponent(0.55 + 0.45 * progress)
        let outline = NSBezierPath(
            roundedRect: bounds.insetBy(
                dx: 0.5,
                dy: 0.5
            ),
            xRadius: bounds.height / 2,
            yRadius: bounds.height / 2
        )
        NSColor.black.withAlphaComponent(0.28).setFill()
        outline.fill()
        NSColor.white.withAlphaComponent(0.16 + 0.14 * progress).setStroke()
        outline.lineWidth = 1
        outline.stroke()

        Icon.draw(
            .microphone,
            in: NSRect(
                x: 15,
                y: (bounds.height - 14) / 2,
                width: 14,
                height: 14
            ),
            color: foreground
        )
        let text = Typography.size(
            title,
            font: font!
        )
        (title as NSString).draw(
            at: NSPoint(
                x: 37,
                y: (bounds.height - text.height) / 2
            ),
            withAttributes: [.font: font!, .foregroundColor: foreground]
        )
        let track = NSRect(
            x: bounds.width - 1 - 7 - 30,
            y: (bounds.height - 18) / 2,
            width: 30,
            height: 18
        )
        let trackColor = NSColor(
            srgbRed: 1 + (47.0 / 255 - 1) * progress,
            green: 1 + (70.0 / 255 - 1) * progress,
            blue: 1 + (226.0 / 255 - 1) * progress,
            alpha: 0.18 + 0.82 * progress
        )
        trackColor.setFill()
        NSBezierPath(
            roundedRect: track,
            xRadius: 9,
            yRadius: 9
        ).fill()
        NSColor.white.setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: track.minX + 2 + 12 * progress,
                y: track.minY + 2,
                width: 14,
                height: 14
            )
        ).fill()
    }

    /// Draws a focus ring around the complete rounded toggle hit area.
    override func drawFocusRingMask() {
        NSBezierPath(
            roundedRect: bounds,
            xRadius: bounds.height / 2,
            yRadius: bounds.height / 2
        ).fill()
    }
}
