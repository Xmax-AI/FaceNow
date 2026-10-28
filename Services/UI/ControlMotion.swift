//
//  ControlMotion.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
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

    /// Commits native opacity immediately while blending from its currently visible value.
    static func setOpacity(
        _ opacity: CGFloat,
        on view: NSView
    ) {
        guard view.alphaValue != opacity else { return }
        let visible = view.layer?.presentation()?.opacity ?? Float(view.alphaValue)
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
            in: view
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
        in view: NSView
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
