//
//  CameraStatusBannerView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import SnapKit

/// Keeps a persistent, wrapping preparation explanation separate from the preview canvas.
@MainActor
final class CameraStatusBannerView: Canvas {

    /// The deep orange used by warning actions in every interaction state.
    private static let actionColor = NSColor(
        srgbRed: 0.65,
        green: 0.30,
        blue: 0.04,
        alpha: 1
    )

    /// Reports the rendered command without owning camera policy or device operations.
    var onAction: ((CameraNoticeAction) -> Void)?

    /// The current immutable content, used only to render and report a click.
    private var presentation: CameraNoticePresentation?

    /// The warning icon aligned with the explanation and setup action.
    private lazy var icon: NSImageView = {
        let view = NSImageView()
        view.image = NSImage(
            systemSymbolName: "exclamationmark.circle",
            accessibilityDescription: nil
        )
        view.contentTintColor = .systemOrange
        return view
    }()

    /// Wraps the complete reason instead of truncating a button title.
    private lazy var messageLabel: NSTextField = {
        let view = makeLabel(
            size: 13,
            color: Palette.secondary
        )
        view.maximumNumberOfLines = 0
        view.lineBreakMode = .byWordWrapping
        view.cell?.wraps = true
        view.cell?.usesSingleLineMode = false
        view.cell?.isScrollable = false
        return view
    }()

    /// Displays the mapped action and any inline operation progress.
    private lazy var setupButton: Button = {
        let view = Button(style: .plain)
        view.font = Typography.font(
            size: 13,
            weight: .medium
        )
        view.foregroundColor = Self.actionColor
        view.hoverBackgroundColor = Self.actionColor.withAlphaComponent(0.08)
        view.leadingPadding = 8
        view.trailingPadding = 8
        view.cornerRadius = 8
        view.showsShadow = false
        view.onClick = { [weak self] in
            guard let self, let presentation = self.presentation,
                presentation.isEnabled, !presentation.isLoading
            else { return }
            self.onAction?(presentation.action)
        }
        return view
    }()

    /// Creates a stable warning layout that remains hidden until a confirmed failure is available.
    init() {
        super.init(
            color: .systemOrange.withAlphaComponent(0.08),
            radius: 12
        )
        isHidden = true
        [icon, messageLabel, setupButton].forEach(addSubview)
        icon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
            make.size.equalTo(18)
        }
        messageLabel.snp.makeConstraints { make in
            make.leading.equalTo(icon.snp.trailing).offset(8)
            make.trailing.equalTo(setupButton.snp.leading).offset(-12)
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview().inset(10)
            make.bottom.lessThanOrEqualToSuperview().inset(10)
        }
        setupButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(12)
            make.centerY.equalToSuperview()
            make.width.equalTo(64)
            make.height.equalTo(28)
        }
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Updates confirmed failures and reports whether visibility or wrapping needs to change.
    func update(
        presentation: CameraNoticePresentation?
    ) -> Bool {
        guard self.presentation != presentation else { return false }
        self.presentation = presentation
        messageLabel.stringValue = presentation?.message ?? ""
        setupButton.title = presentation?.buttonTitle ?? ""
        setupButton.loading = presentation?.isLoading ?? false
        setupButton.isEnabled = presentation?.isEnabled ?? false
        setupButton.setAccessibilityLabel(presentation?.buttonTitle ?? "")
        setupButton.setAccessibilityHelp(presentation?.message ?? "")
        setupButton.snp.updateConstraints { make in make.width.equalTo(actionWidth) }
        isHidden = presentation == nil
        return true
    }

    /// Measures the button through the shared native component instead of assuming a short label.
    private var actionWidth: CGFloat { max(64, setupButton.preferredWidth) }

    /// Measures the wrapped explanation using the same content insets as the installed constraints.
    func preferredHeight(
        width: CGFloat
    ) -> CGFloat {
        guard !isHidden else { return 0 }
        let textWidth = max(1, width - 62 - actionWidth)
        if messageLabel.preferredMaxLayoutWidth != textWidth {
            messageLabel.preferredMaxLayoutWidth = textWidth
        }
        let height = messageLabel.intrinsicContentSize.height
        return max(44, ceil(height) + 20)
    }
}
