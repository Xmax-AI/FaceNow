//
//  GenerationPromptTextView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import SnapKit

/// Draws the placeholder at the text origin and preserves input-method composition.
final class GenerationPromptTextView: NSTextView {

    /// The hint drawn only while no committed or marked text is present.
    var placeholder = "" { didSet { needsDisplay = true } }

    /// The color used to draw the empty-editor hint.
    var placeholderColor: NSColor = .placeholderTextColor

    /// Receives committed text after input-method composition has completed.
    var onCommittedTextChange: ((String) -> Void)?

    /// The nested native input operations that defer committed-text delivery.
    private var inputOperationDepth = 0

    /// Whether the editor has neither text nor an active marked-text range.
    var showsPlaceholder: Bool { string.isEmpty && !hasMarkedText() }

    /// The editor contents whose replacement invalidates placeholder presentation.
    override var string: String {
        didSet {
            needsDisplay = true
            invalidateIntrinsicContentSize()
        }
    }

    /// The last width used to measure wrapping in the native text container.
    private var measuredWidth: CGFloat = -1

    /// Supplies a content-driven document height to the scroll view's SnapKit constraints.
    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 0)
        }
        layoutManager.ensureLayout(for: textContainer)
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: ceil(layoutManager.usedRect(for: textContainer).height + textContainerInset.height * 2)
        )
    }

    /// Remeasures wrapping when Auto Layout changes the editor width.
    override func layout() {
        super.layout()
        guard measuredWidth != bounds.width else { return }
        measuredWidth = bounds.width
        invalidateIntrinsicContentSize()
    }

    /// Draws the empty-editor hint at the native text-container origin.
    override func draw(
        _ dirtyRect: NSRect
    ) {
        super.draw(dirtyRect)
        guard showsPlaceholder else { return }
        let origin = textContainerOrigin
        let padding = textContainer?.lineFragmentPadding ?? 0
        (placeholder as NSString).draw(
            at: NSPoint(
                x: origin.x + padding,
                y: origin.y
            ),
            withAttributes: [
                .font: font ?? NSFont.systemFont(ofSize: 15),
                .foregroundColor: placeholderColor,
            ]
        )
    }

    /// Refreshes placeholder state after a native text change.
    override func didChangeText() {
        super.didChangeText()
        updateInputState()
    }

    /// Defers prompt publication while the input method replaces its marked range.
    override func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        inputOperationDepth += 1
        defer { finishInputOperation() }
        super.setMarkedText(
            string,
            selectedRange: selectedRange,
            replacementRange: replacementRange
        )
    }

    /// Publishes inserted text after the native replacement operation completes.
    override func insertText(
        _ string: Any,
        replacementRange: NSRange
    ) {
        inputOperationDepth += 1
        defer { finishInputOperation() }
        super.insertText(
            string,
            replacementRange: replacementRange
        )
    }

    /// Completes input-method composition before publishing the resulting prompt.
    override func unmarkText() {
        inputOperationDepth += 1
        defer { finishInputOperation() }
        super.unmarkText()
    }

    /// Releases one input-operation level and reevaluates committed text.
    private func finishInputOperation() {
        inputOperationDepth -= 1
        updateInputState()
    }

    /// Publishes only text that is outside all active composition operations.
    private func updateInputState() {
        needsDisplay = true
        invalidateIntrinsicContentSize()
        guard inputOperationDepth == 0, !hasMarkedText() else { return }
        onCommittedTextChange?(string)
    }
}
