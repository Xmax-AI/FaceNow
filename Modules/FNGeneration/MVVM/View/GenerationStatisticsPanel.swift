//
//  GenerationStatisticsPanel.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit

/// A persistent overlay displaying one group of formatted generation metrics.
final class GenerationStatisticsPanel: Canvas {

    /// The title and value labels retained for each metric row.
    private var labels: [(NSTextField, NSTextField)] = []

    /// The separators retained before total-measurement rows.
    private var dividers: [NSView] = []

    /// The current metric rows corresponding to the retained native labels.
    private var rows: [GenerationStatisticsRow]

    /// The measured overlay height including emphasized total rows.
    let panelHeight: CGFloat

    /// The measured overlay width required by the current labels and values.
    private(set) var panelWidth: CGFloat = 0

    /// Creates the group's persistent labels and total-row dividers.
    init(
        group: GenerationStatisticsGroup
    ) {
        rows = group.rows
        panelHeight = 16 + CGFloat(group.rows.count) * 16.5 + CGFloat(group.rows.filter(\.total).count) * 11
        super.init(
            color: .black.withAlphaComponent(0.6),
            radius: 10
        )
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        setAccessibilityLabel(group.id)
        for row in group.rows {
            if row.total {
                let divider = Canvas(color: .white.withAlphaComponent(0.18))
                addSubview(divider)
                dividers.append(divider)
            }
            let label = makeLabel(
                row.id,
                size: 11,
                color: .white.withAlphaComponent(0.9),
                weight: row.total ? .semibold : .regular
            )
            let value = makeLabel(
                row.value,
                size: 11,
                color: .white.withAlphaComponent(0.9)
            )
            value.font = Typography.font(
                size: 11,
                weight: row.total ? .semibold : .regular
            )
            value.attributedStringValue = Typography.numericText(
                row.value,
                size: 11,
                weight: row.total ? .semibold : .regular,
                color: .white.withAlphaComponent(0.9)
            )
            value.alignment = .right
            label.toolTip = row.help
            value.toolTip = row.help
            addSubview(label)
            addSubview(value)
            labels.append((label, value))
        }
        update(group)
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Updates formatted values and expands the panel only when measurement requires it.
    func update(
        _ group: GenerationStatisticsGroup
    ) {
        rows = group.rows
        var width: CGFloat = 0
        for (row, pair) in zip(
            group.rows,
            labels
        ) {
            if pair.1.stringValue != row.value {
                pair.1.attributedStringValue = Typography.numericText(
                    row.value,
                    size: 11,
                    weight: row.total ? .semibold : .regular,
                    color: .white.withAlphaComponent(0.9)
                )
                // A value can gain a digit without changing the panel's widest row.
                needsLayout = true
            }
            if pair.0.toolTip != row.help {
                pair.0.toolTip = row.help
                pair.1.toolTip = row.help
            }
            let titleWidth = Typography.size(
                row.id,
                font: pair.0.font!
            ).width
            let valueWidth = max(
                64,
                pair.1.attributedStringValue.size().width
            )
            width = max(width, titleWidth + 16 + valueWidth + 20)
        }
        if panelWidth != ceil(width) {
            panelWidth = ceil(width)
            needsLayout = true
            superview?.needsLayout = true
        }
    }

    /// Places metric labels and total-row dividers within the measured panel.
    override func layout() {
        super.layout()
        var y: CGFloat = 8
        var dividerIndex = 0
        for (row, pair) in zip(
            rows,
            labels
        ) {
            if row.total {
                dividers[dividerIndex].frame = NSRect(
                    x: 10,
                    y: y + 5,
                    width: bounds.width - 20,
                    height: 1
                )
                dividerIndex += 1
                y += 11
            }
            let valueWidth = max(
                64,
                ceil(
                    pair.1.attributedStringValue.size().width
                )
            )
            // Compensate for NSTextField's 2pt cell inset so the visible text matches the Web padding.
            pair.0.frame = NSRect(
                x: 8,
                y: y,
                width: bounds.width - 20 - valueWidth - 16 + 4,
                height: 16.5
            )
            pair.1.frame = NSRect(
                x: bounds.width - 10 - valueWidth - 2,
                y: y,
                width: valueWidth + 4,
                height: 16.5
            )
            y += 16.5
        }
    }
}
