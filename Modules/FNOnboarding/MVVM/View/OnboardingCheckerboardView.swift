//
//  OnboardingCheckerboardView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit

/// The same 38pt checkerboard cells as the Web landing page.
final class OnboardingCheckerboardView: Canvas {

    /// Creates the clipped checkerboard canvas used by the initial camera-start page.
    init() {
        super.init(radius: 24)
        layer?.masksToBounds = true
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Draws opaque checkerboard tiles without fractional-edge seams.
    override func draw(
        _ dirtyRect: NSRect
    ) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        // An opaque base and hard tile edges prevent seams at fractional view origins.
        context.setShouldAntialias(false)
        context.setFillColor(
            NSColor(
                srgbRed: 55 / 255,
                green: 55 / 255,
                blue: 59 / 255,
                alpha: 1
            ).cgColor
        )
        context.fill(bounds)
        context.setFillColor(
            NSColor(
                srgbRed: 67 / 255,
                green: 67 / 255,
                blue: 71 / 255,
                alpha: 1
            ).cgColor
        )
        for row in 0...Int(bounds.height / 38) {
            for column in 0...Int(bounds.width / 38) where (row + column).isMultiple(of: 2) {
                context.fill(
                    CGRect(
                        x: column * 38,
                        y: row * 38,
                        width: 38,
                        height: 38
                    )
                )
            }
        }
    }
}
