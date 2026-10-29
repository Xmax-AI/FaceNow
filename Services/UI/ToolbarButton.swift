//
//  ToolbarButton.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import SnapKit

/// Shares compact native button surfaces and geometry across home and generation toolbars.
final class ToolbarButton: Button {

    /// The two shapes supported by the common toolbar component.
    enum Shape {

        /// A content-sized capsule for text and icon actions.
        case capsule

        /// A circular action whose width always follows its height.
        case circle
    }

    /// Determines both native constraints and the width reported to the parent toolbar.
    let shape: Shape

    /// Creates a toolbar control with shared metrics and an optional semantic color role.
    init(
        _ title: String = "",
        icon: Icon.Kind? = nil,
        style: Appearance = .pill,
        shape: Shape = .capsule,
        chevron: Bool = false,
        weight: NSFont.Weight = .regular
    ) {
        self.shape = shape
        super.init(
            title,
            icon: icon,
            style: style
        )
        self.chevron = chevron
        configureForToolbar(
            weight: weight
        )
        if icon == .lightning {
            iconSize = 15
        }
        switch style {
        case .statistics, .volume:
            iconSize = 18
        case .destructive where icon == .stop:
            iconSize = 12
        default:
            break
        }
        if shape == .circle {
            iconSize = 18
            leadingPadding = 0
            trailingPadding = 0
            centersSymbolVisually = true
            snp.makeConstraints { make in
                make.width.equalTo(snp.height)
            }
        }
    }

    /// Storyboard decoding is unsupported for this programmatic control.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Measures circles using the same row height that their constraints follow.
    func preferredWidth(
        controlHeight: CGFloat
    ) -> CGFloat {
        shape == .circle ? max(0, controlHeight) : preferredWidth
    }
}
