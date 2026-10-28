//
//  HomeErrorView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit

/// Presents a selectable error message without owning session failures or timers.
@MainActor
final class HomeErrorView: Canvas {

    /// Requests dismissal of the coordinator's current error.
    var onDismiss: (() -> Void)?

    /// The error symbol displayed beside the message.
    private lazy var toastIcon: NSImageView = {
        let view = NSImageView()
        view.image = NSImage(
            systemSymbolName: "exclamationmark.circle",
            accessibilityDescription: nil
        )
        view.contentTintColor = .systemRed
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }()

    /// The native selectable message label.
    private lazy var toastMessage: NSTextField = {
        let view = makeLabel(size: 14)
        view.maximumNumberOfLines = 0
        view.lineBreakMode = .byWordWrapping
        view.cell?.usesSingleLineMode = false
        view.cell?.wraps = true
        view.cell?.isScrollable = false
        view.isSelectable = true
        return view
    }()

    /// The explicit dismissal control.
    private lazy var toastDismiss: Button = {
        let view = Button(
            "×",
            style: .plain
        )
        view.setAccessibilityLabel("Dismiss")
        view.onClick = { [weak self] in self?.onDismiss?() }
        return view
    }()

    /// Creates the persistent notification controls.
    init() {
        super.init(
            color: .white.withAlphaComponent(0.96),
            radius: 14
        )

        [toastIcon, toastMessage, toastDismiss].forEach(addSubview)
        layer?.borderWidth = 1
        layer?.borderColor = Palette.text.withAlphaComponent(0.08).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.14
        layer?.shadowRadius = 16

        layer?.shadowOffset = CGSize(
            width: 0,
            height: 8
        )
    }

    /// Storyboard decoding is unsupported for this programmatic view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Applies the current error and announces only a newly presented message.
    func update(
        message: String?,
        announce: Bool
    ) {
        isHidden = message == nil
        toastMessage.stringValue = message ?? ""
        if announce, let message {
            NSAccessibility.post(
                element: toastMessage,
                notification: .announcementRequested,
                userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue]
            )
        }
    }

    /// Centers the wrapped notification inside the window content.
    func place(
        in contentBounds: NSRect
    ) {
        let accessoryWidth: CGFloat = 16 * 2 + 20 + 24 + 10 * 2
        let maximumWidth = min(560, max(0, contentBounds.width - 56))
        let naturalTextWidth = ceil(toastMessage.attributedStringValue.size().width) + 4
        let width = min(maximumWidth, naturalTextWidth + accessoryWidth)
        let textWidth = max(1, width - accessoryWidth)
        let textHeight = ceil(
            toastMessage.cell?.cellSize(
                forBounds: NSRect(
                    x: 0,
                    y: 0,
                    width: textWidth,
                    height: .greatestFiniteMagnitude
                )
            ).height ?? 0
        )
        let height = max(textHeight, 20, 24) + 24
        frame = NSRect(
            x: (contentBounds.width - width) / 2,
            y: 84,
            width: width,
            height: height
        )
        toastIcon.frame = NSRect(
            x: 16,
            y: (height - 20) / 2,
            width: 20,
            height: 20
        )
        toastMessage.frame = NSRect(
            x: 46,
            y: (height - textHeight) / 2,
            width: textWidth,
            height: textHeight
        )
        toastDismiss.frame = NSRect(
            x: width - 40,
            y: (height - 24) / 2,
            width: 24,
            height: 24
        )
    }

}
