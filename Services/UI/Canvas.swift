//
//  Canvas.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit

/// Top-left coordinates shared by the manually laid out native pages.
class Canvas: NSView {

    /// Whether layout coordinates start at the top-left corner.
    override var isFlipped: Bool { true }

    /// Creates a layer-backed canvas using top-left layout coordinates.
    init(
        color: NSColor = .clear,
        radius: CGFloat = 0
    ) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = radius
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }
}

/// Creates a native label with the shared product typography and truncation behavior.
@MainActor
func makeLabel(
    _ title: String = "",
    size: CGFloat = 13,
    color: NSColor = Palette.text,
    weight: NSFont.Weight = .regular
) -> NSTextField {
    let label = TextLabel(labelWithString: title)
    label.font = Typography.font(
        size: size,
        weight: weight
    )
    label.textColor = color
    label.lineBreakMode = .byTruncatingTail
    return label
}

/// Decorative labels let clicks reach the native control underneath them.
private final class TextLabel: NSTextField {

    /// Preserves text selection while allowing decorative content to pass through pointer events.
    override func hitTest(
        _ point: NSPoint
    ) -> NSView? {
        isSelectable ? super.hitTest(point) : nil
    }
}
