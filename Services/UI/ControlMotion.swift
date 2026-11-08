//
//  ControlMotion.swift
//  FaceNow
//

import AppKit

/// Shares interruptible timing for interactive control colors and opacity.
@MainActor
enum ControlMotion {

    /// The standard interaction transition duration, in seconds.
    static let duration: TimeInterval = 0.3

    /// Whether a mounted control may animate under the current accessibility preferences.
    static func isAnimated(
        in view: NSView
    ) -> Bool {
        view.window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Runs a native animatable-property change using the shared control timing.
    static func animate(
        in view: NSView,
        changes: () -> Void
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = isAnimated(in: view) ? duration : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            changes()
        }
    }

    /// Shares onboarding's backdrop fade, decelerating entrance, and reversible vertical exit.
    static func setModalVisible(
        _ visible: Bool,
        backdrop: NSView,
        card: NSView,
        in host: NSView,
        layoutChanges: () -> Void
    ) {
        for surface in [backdrop, card] {
            set(
                Float(visible ? 1 : 0),
                for: "opacity",
                on: surface.layer,
                in: host
            )
        }
        host.layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = isAnimated(in: host) ? duration : 0
            context.timingFunction =
                visible
                ? CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
                : CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            layoutChanges()
            host.layoutSubtreeIfNeeded()
        }
    }

    /// Gives rejected input a brief horizontal shake without changing its constrained geometry.
    static func shake(
        _ view: NSView
    ) {
        guard let layer = view.layer else { return }
        let visible = layer.presentation()?.value(forKeyPath: "transform.translation.x") as? NSNumber ?? 0
        stopShake(in: view)
        guard isAnimated(in: view), !view.isHiddenOrHasHiddenAncestor else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [visible, -6, 6, -4, 4, -2, 2, 0]
        animation.keyTimes = [0, 0.12, 0.26, 0.4, 0.54, 0.68, 0.82, 1]
        animation.duration = duration
        animation.calculationMode = .cubic
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isAdditive = true
        layer.add(animation, forKey: "ControlMotion.shake")
    }

    /// Drops only validation motion when a control is hidden or detached.
    static func stopShake(
        in view: NSView
    ) {
        view.layer?.removeAnimation(forKey: "ControlMotion.shake")
    }

    /// Blends premultiplied sRGB components so transparent fills never introduce a dark midpoint.
    nonisolated static func blend(
        _ start: NSColor,
        toward end: NSColor,
        progress: CGFloat
    ) -> NSColor {
        let amount = min(1, max(0, progress))
        if amount == 0 { return start }
        if amount == 1 { return end }
        guard let source = start.usingColorSpace(.extendedSRGB),
            let destination = end.usingColorSpace(.extendedSRGB)
        else { return start.blended(withFraction: amount, of: end) ?? end }
        let sourceWeight = source.alphaComponent * (1 - amount)
        let destinationWeight = destination.alphaComponent * amount
        let alpha = sourceWeight + destinationWeight
        guard alpha > 0 else { return end.withAlphaComponent(0) }
        return NSColor(
            srgbRed: (source.redComponent * sourceWeight + destination.redComponent * destinationWeight) / alpha,
            green: (source.greenComponent * sourceWeight + destination.greenComponent * destinationWeight) / alpha,
            blue: (source.blueComponent * sourceWeight + destination.blueComponent * destinationWeight) / alpha,
            alpha: alpha
        )
    }

    /// Blends native opacity from its visible value, or an explicit start for newly revealed content.
    static func setOpacity(
        _ opacity: CGFloat,
        on view: NSView,
        from initialOpacity: CGFloat? = nil,
        duration: TimeInterval = ControlMotion.duration
    ) {
        guard view.alphaValue != opacity || initialOpacity != nil else { return }
        let visible = initialOpacity.map { Float($0) } ?? view.layer?.presentation()?.opacity ?? Float(view.alphaValue)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.alphaValue = opacity
        CATransaction.commit()
        guard let layer = view.layer else { return }
        transition(
            layer,
            keyPath: "opacity",
            from: visible,
            to: Float(opacity),
            in: view,
            duration: duration
        )
    }

    /// Updates a layer property once and preserves any in-flight presentation on interruption.
    static func set(
        _ value: Any,
        for keyPath: String,
        on layer: CALayer?,
        in view: NSView
    ) {
        guard let layer else { return }
        let current = layer.value(forKeyPath: keyPath)
        if let current = current as? NSObject, let next = value as? NSObject, current.isEqual(next) { return }
        let visible = layer.presentation()?.value(forKeyPath: keyPath) ?? current
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(value, forKeyPath: keyPath)
        CATransaction.commit()
        transition(
            layer,
            keyPath: keyPath,
            from: visible,
            to: value,
            in: view
        )
    }

    /// Replaces only this property's animation; equal-target refreshes never restart it.
    private static func transition(
        _ layer: CALayer,
        keyPath: String,
        from start: Any?,
        to end: Any,
        in view: NSView,
        duration: TimeInterval = ControlMotion.duration
    ) {
        let key = "ControlMotion.\(keyPath)"
        guard isAnimated(in: view), let start else {
            layer.removeAnimation(forKey: key)
            return
        }
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = start
        animation.toValue = end
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(
            animation,
            forKey: key
        )
    }
}
