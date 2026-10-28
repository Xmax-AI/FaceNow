//
//  Spinner.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit

/// Keeps the Web loading ring independent of control state updates.
final class Spinner: Canvas {

    /// The shape layer retaining the loading arc and its rotation animation.
    private let ring = CAShapeLayer()

    /// Creates a decorative loading arc with the supplied stroke color.
    init(
        color: NSColor = .white
    ) {
        super.init()
        ring.fillColor = nil
        ring.strokeColor = color.cgColor
        ring.lineWidth = 2
        ring.strokeEnd = 0.72
        ring.lineCap = .round
        layer?.addSublayer(ring)
        setAccessibilityElement(false)
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Starts or removes the arc rotation while respecting reduced-motion preferences.
    func setSpinning(
        _ spinning: Bool,
        color: NSColor
    ) {
        ring.strokeColor = color.cgColor
        isHidden = !spinning
        guard spinning, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            ring.removeAnimation(forKey: "spin")
            return
        }
        guard ring.animation(forKey: "spin") == nil else { return }
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.toValue = Double.pi * 2
        animation.duration = 0.8
        animation.repeatCount = .infinity
        ring.add(
            animation,
            forKey: "spin"
        )
    }

    /// Updates the arc path without animating incidental geometry changes.
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.frame = bounds
        ring.path = CGPath(
            ellipseIn: bounds.insetBy(
                dx: 2,
                dy: 2
            ),
            transform: nil
        )
        CATransaction.commit()
    }
}
