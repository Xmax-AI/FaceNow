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
import SnapKit

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
        setAccessibilityLabel(group.title)
        for row in group.rows {
            if row.total {
                let divider = Canvas(color: .white.withAlphaComponent(0.18))
                addSubview(divider)
                dividers.append(divider)
            }
            let label = makeLabel(
                row.title,
                size: 11,
                color: .white.withAlphaComponent(0.9),
                weight: row.total ? .semibold : .regular
            )
            label.font = .systemFont(ofSize: 11, weight: row.total ? .semibold : .regular)
            let value = makeLabel(
                row.value,
                size: 11,
                color: .white.withAlphaComponent(0.9)
            )
            value.font = .systemFont(
                ofSize: 11,
                weight: row.total ? .semibold : .regular
            )
            value.alignment = .right
            label.toolTip = row.help
            value.toolTip = row.help
            addSubview(label)
            addSubview(value)
            labels.append((label, value))
        }
        configureLayout()
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
                pair.1.stringValue = row.value
                pair.1.snp.updateConstraints { make in
                    make.width.equalTo(max(64, ceil(Typography.size(pair.1.stringValue, font: pair.1.font!).width)) + 4)
                }
            }
            if pair.0.toolTip != row.help {
                pair.0.toolTip = row.help
                pair.1.toolTip = row.help
            }
            let titleWidth = Typography.size(
                row.title,
                font: pair.0.font!
            ).width
            let valueWidth = max(
                64,
                Typography.size(pair.1.stringValue, font: pair.1.font!).width
            )
            width = max(width, titleWidth + 16 + valueWidth + 20)
        }
        if panelWidth != ceil(width) {
            panelWidth = ceil(width)
            needsLayout = true
            if superview != nil { snp.updateConstraints { make in make.width.equalTo(panelWidth) } }
        }
    }

    /// Aligns metric rows and their native text baselines without assigning frames.
    private func configureLayout() {
        var previous: NSTextField?
        var dividerIndex = 0
        for (row, pair) in zip(rows, labels) {
            pair.0.snp.makeConstraints { make in
                make.leading.equalToSuperview().offset(8)
                make.trailing.equalTo(pair.1.snp.leading).offset(-12)
                make.height.equalTo(16.5)
                if let previous {
                    make.top.equalTo(previous.snp.bottom).offset(row.total ? 11 : 0)
                } else {
                    make.top.equalToSuperview().offset(row.total ? 19 : 8)
                }
            }
            pair.1.snp.makeConstraints { make in
                make.trailing.equalToSuperview().inset(8)
                // SnapKit maps lastBaseline on AppKit; firstBaseline is only mapped on UIKit.
                make.lastBaseline.equalTo(pair.0.snp.lastBaseline)
                make.height.equalTo(16.5)
                make.width.equalTo(max(64, ceil(Typography.size(pair.1.stringValue, font: pair.1.font!).width)) + 4)
            }
            if row.total {
                dividers[dividerIndex].snp.makeConstraints { make in
                    make.leading.trailing.equalToSuperview().inset(10)
                    make.top.equalTo(pair.0.snp.top).offset(-6)
                    make.height.equalTo(1)
                }
                dividerIndex += 1
            }
            previous = pair.0
        }
    }
}
