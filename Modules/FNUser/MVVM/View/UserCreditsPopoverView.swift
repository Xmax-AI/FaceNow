//
//  UserCreditsPopoverView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import SnapKit

/// Explains the low-credit warning and keeps its recharge action reachable on hover.
@MainActor
final class UserCreditsPopoverView: Canvas {

    /// Opens the existing credit purchase page through the owning account view.
    var onRecharge: (() -> Void)?

    /// Keeps the popover open while the pointer moves onto its contents.
    var onHoverChanged: ((Bool) -> Void)?

    /// Tracks the entire card, including its child controls.
    private var hoverArea: NSTrackingArea?

    /// Matches the warning pill's red visual treatment.
    private lazy var warningIcon: Button = {
        let view = Button(style: .destructive)
        view.symbolName = "exclamationmark.triangle.fill"
        view.iconSize = 16
        view.leadingPadding = 0
        view.trailingPadding = 0
        view.cornerRadius = 9
        view.passive = true
        view.showsShadow = false
        view.setAccessibilityElement(false)
        return view
    }()

    /// States the reason for the warning without repeating the balance.
    private lazy var titleLabel: NSTextField = {
        let view = NSTextField(labelWithString: "Low credits")
        view.font = Typography.font(
            size: 14,
            weight: .semibold
        )
        view.textColor = Palette.text
        return view
    }()

    /// Explains the next action in the same language as the application.
    private lazy var messageLabel: NSTextField = {
        let view = NSTextField(wrappingLabelWithString: "You're running low on credits. Top up to avoid interruptions.")
        view.font = Typography.font(size: 12)
        view.textColor = Palette.secondary
        view.preferredMaxLayoutWidth = 248
        return view
    }()

    /// Provides a direct route to the account's existing recharge page.
    private lazy var rechargeButton: Button = {
        let view = Button(
            "Buy Credits",
            style: .primary
        )
        view.font = Typography.font(
            size: 12,
            weight: .medium
        )
        view.cornerRadius = 8
        view.showsShadow = false
        view.onClick = { [weak self] in self?.onRecharge?() }
        return view
    }()

    /// Creates a compact card whose text determines its height.
    init() {
        super.init(
            color: .white,
            radius: 12
        )
        [warningIcon, titleLabel, messageLabel, rechargeButton].forEach(addSubview)
        snp.makeConstraints { make in
            make.width.equalTo(280)
        }
        warningIcon.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(16)
            make.size.equalTo(32)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(warningIcon.snp.trailing).offset(10)
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalTo(warningIcon)
        }
        messageLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.top.equalTo(warningIcon.snp.bottom).offset(12)
        }
        rechargeButton.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview().inset(16)
            make.top.equalTo(messageLabel.snp.bottom).offset(14)
            make.height.equalTo(32)
        }
    }

    /// Storyboard decoding is unsupported for this programmatic view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Refreshes pointer tracking when the native popover changes size.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        hoverArea = area
    }

    /// Cancels delayed dismissal while the pointer is over the card.
    override func mouseEntered(
        with event: NSEvent
    ) {
        onHoverChanged?(true)
    }

    /// Allows dismissal after the pointer leaves both the card and its source pill.
    override func mouseExited(
        with event: NSEvent
    ) {
        onHoverChanged?(false)
    }
}
