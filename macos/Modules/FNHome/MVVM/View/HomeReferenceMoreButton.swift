//
//  HomeReferenceMoreButton.swift
//  FaceNow
//

import AppKit

/// Opens the home catalog with the same dashed circular plus used by Windows.
@MainActor
final class HomeReferenceMoreButton: Button {

    init() {
        super.init(icon: .plus, style: .plain)
        iconSize = 22
        foregroundColor = .white.withAlphaComponent(0.85)
        hoverBackgroundColor = .white.withAlphaComponent(0.08)
        cornerRadius = 26
        showsShadow = false
        toolTip = HomeStrings.referenceImages
        setAccessibilityLabel(HomeStrings.referenceImages)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: NSRect(x: bounds.midX - 25, y: bounds.midY - 25, width: 50, height: 50))
        circle.setLineDash([3, 3], count: 2, phase: 0)
        circle.lineWidth = 1.5
        NSColor.white.withAlphaComponent(isEnabled ? 0.85 : 0.4).setStroke()
        circle.stroke()
        super.draw(dirtyRect)
    }
}
