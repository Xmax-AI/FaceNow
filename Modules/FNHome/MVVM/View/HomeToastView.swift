//
//  HomeToastView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import SnapKit

/// Presents selectable success and error notifications without owning business state.
@MainActor
final class HomeToastView: Canvas {

    /// The semantic appearance of the transient notification.
    enum Style {

        /// A failure requiring the user's attention.
        case error

        /// A successfully completed user action.
        case success
    }

    /// Hides the view only after its fade completes, and is cancelled by a newer message.
    private var dismissal: Task<Void, Never>?

    /// Whether the host placement constraints have been installed.
    private var placementInstalled = false

    /// The horizontal inset shared by notification placement and child constraints.
    private static let horizontalInset: CGFloat = 12

    /// The gap separating the message from each accessory.
    private static let contentSpacing: CGFloat = 8

    /// The dismissal hit area, independent of its visible symbol size.
    private static let dismissSize: CGFloat = 32

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
        let view = Button(style: .plain)
        view.symbolName = "xmark"
        view.iconSize = 16
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
        isHidden = true

        [toastIcon, toastMessage, toastDismiss].forEach(addSubview)
        toastIcon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.horizontalInset)
            make.centerY.equalToSuperview()
            make.size.equalTo(20)
        }
        toastDismiss.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(Self.horizontalInset)
            make.centerY.equalToSuperview()
            make.size.equalTo(Self.dismissSize)
        }
        toastMessage.snp.makeConstraints { make in
            make.leading.equalTo(toastIcon.snp.trailing).offset(Self.contentSpacing)
            make.trailing.equalTo(toastDismiss.snp.leading).offset(-Self.contentSpacing)
            make.centerY.equalToSuperview()
            make.height.equalTo(20)
        }
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

    /// Gives the notification valid dimensions as soon as its host is available.
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let superview else { return }
        place(in: superview.bounds)
    }

    /// Applies a notification and announces only a newly presented message.
    func update(
        message: String?,
        announce: Bool,
        style: Style = .error
    ) {
        guard let message else {
            guard !isHidden, dismissal == nil else { return }
            ControlMotion.setOpacity(0, on: self)
            guard ControlMotion.isAnimated(in: self) else {
                isHidden = true
                return
            }
            dismissal = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(ControlMotion.duration)) } catch { return }
                self?.isHidden = true
                self?.dismissal = nil
            }
            return
        }
        dismissal?.cancel()
        dismissal = nil
        toastMessage.stringValue = message
        toastIcon.image = NSImage(
            systemSymbolName: style == .success ? "checkmark.circle.fill" : "exclamationmark.circle",
            accessibilityDescription: nil
        )
        toastIcon.contentTintColor = style == .success ? .systemGreen : .systemRed
        if isHidden {
            alphaValue = 0
            isHidden = false
        }
        ControlMotion.setOpacity(1, on: self)
        if announce {
            NSAccessibility.post(
                element: toastMessage,
                notification: .announcementRequested,
                userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue]
            )
        }
    }

    /// Cancels view-bound fading when the owning application shuts down.
    func shutdown() {
        dismissal?.cancel()
        dismissal = nil
        isHidden = true
    }

    /// Centers the wrapped notification inside the window content.
    func place(
        in contentBounds: NSRect
    ) {
        let accessoryWidth = Self.horizontalInset * 2 + 20 + Self.dismissSize + Self.contentSpacing * 2
        let maximumWidth = min(560, max(accessoryWidth + 1, contentBounds.width - 56))
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
        let height = max(textHeight, 20, Self.dismissSize) + 16
        if !placementInstalled {
            snp.makeConstraints { make in
                make.centerX.equalToSuperview()
                make.top.equalToSuperview().offset(84)
                make.width.equalTo(width)
                make.height.equalTo(height)
            }
            placementInstalled = true
        } else {
            snp.updateConstraints { make in
                make.width.equalTo(width)
                make.height.equalTo(height)
            }
        }
        toastMessage.snp.updateConstraints { make in make.height.equalTo(textHeight) }
    }

}
