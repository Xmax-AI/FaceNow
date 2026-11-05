//
//  GenerationAudioControlsView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import SnapKit

/// Aligns microphone selection and status with the trailing audio and video adjustments action.
@MainActor
final class GenerationAudioControlsView: Canvas {

    /// The matching top and bottom space around standard toolbar controls.
    private static let verticalInset: CGFloat = 8

    /// The matching leading and trailing space inside the audio toolbar.
    private static let horizontalInset: CGFloat = 16

    /// The complete row height shared by workspace measurement and native constraints.
    static let preferredHeight = ToolbarControlMetrics.compactHeight + 2 * verticalInset

    /// Derives presentation from the shared generation state.
    private let viewModel = GenerationAudioControlsViewModel()

    /// Selects physical microphone input through the existing native device list.
    private lazy var microphonePicker: HomeInputPickerView = {
        let view = HomeInputPickerView(input: .microphone, presentation: .toolbar)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        return view
    }()

    /// Indicates input availability independently of remote generated audio.
    private lazy var statusDot: Canvas = {
        let view = Canvas(radius: 4)
        view.setAccessibilityElement(false)
        return view
    }()

    /// Uses the same glyph centering as both adjacent toolbar buttons.
    private lazy var statusLabel: ToolbarButton = {
        let view = ToolbarButton(style: .plain)
        view.foregroundColor = Palette.secondary
        view.leadingPadding = 0
        view.trailingPadding = 0
        view.alignment = .left
        view.centersTitleVisually = true
        view.passive = true
        view.isEnabled = false
        view.setAccessibilityRole(.staticText)
        return view
    }()

    /// Opens existing monitoring and result beauty settings in a native popover.
    private lazy var adjustmentButton: ToolbarButton = {
        let view = ToolbarButton(
            GenerationStrings.audioVideoAdjustments,
            style: .plain,
            weight: .semibold
        )
        view.symbolName = "slider.horizontal.3"
        view.foregroundColor = Palette.accent
        view.restingBackgroundColor = Palette.accent.withAlphaComponent(0.12)
        view.hoverBackgroundColor = Palette.accent.withAlphaComponent(0.18)
        view.trailingPadding = ToolbarControlMetrics.trailingPadding
        view.cornerRadius = 16
        view.centersTitleVisually = true
        view.setAccessibilityLabel(GenerationStrings.audioVideoAdjustments)
        view.onClick = { [weak self] in self?.showAdjustments() }
        return view
    }()

    /// Retains only the currently displayed transient settings card.
    private var adjustmentPopover: NSPopover?

    /// Installs one stable constraint graph with shared control height and centerline.
    init() {
        super.init(color: .white, radius: 16)
        layer?.borderWidth = 1
        layer?.borderColor = Palette.border.cgColor
        [microphonePicker, statusDot, statusLabel, adjustmentButton].forEach(addSubview)
        microphonePicker.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.horizontalInset)
            make.top.bottom.equalToSuperview().inset(Self.verticalInset)
        }
        statusDot.snp.makeConstraints { make in
            make.leading.equalTo(microphonePicker.snp.trailing).offset(20)
            make.centerY.equalTo(microphonePicker)
            make.size.equalTo(8)
        }
        statusLabel.snp.makeConstraints { make in
            make.leading.equalTo(statusDot.snp.trailing).offset(6)
            make.top.bottom.equalTo(microphonePicker)
            make.width.equalTo(
                GenerationAudioControlsViewModel.MicrophoneStatus.allCases
                    .map { statusLabel.preferredWidth(for: $0.title) }.max() ?? 0
            )
            make.trailing.lessThanOrEqualTo(adjustmentButton.snp.leading).offset(-20)
        }
        adjustmentButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(Self.horizontalInset)
            make.top.bottom.equalTo(microphonePicker)
            make.width.equalTo(adjustmentButton.preferredWidth)
        }
        update()
    }

    /// Storyboard decoding is unsupported for this programmatic toolbar.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Reflects repository state without changing control widths when status changes.
    func update() {
        microphonePicker.update()
        let status = viewModel.microphoneStatus
        statusLabel.title = status.title
        statusLabel.setAccessibilityLabel(status.title)
        let color: NSColor =
            switch status {
            case .ready: .systemGreen
            case .disabled: .systemRed
            case .switching: .systemOrange
            case .unavailable: .systemRed
            }
        ControlMotion.set(color.cgColor, for: "backgroundColor", on: statusDot.layer, in: self)
        adjustmentButton.isEnabled = viewModel.canAdjust
        if !viewModel.canAdjust { closePopovers() }
    }

    /// Releases device and adjustment menus before page navigation or teardown.
    func closePopovers() {
        microphonePicker.closePicker()
        adjustmentPopover?.close()
        adjustmentPopover = nil
    }

    /// Closes transient menus when the workspace is hidden.
    override func viewDidHide() {
        super.viewDidHide()
        closePopovers()
    }

    /// Closes transient menus when the toolbar leaves its native window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { closePopovers() }
    }

    /// Opens a single native settings card without changing any effect or audio intent.
    private func showAdjustments() {
        if adjustmentPopover?.isShown == true {
            closePopovers()
            return
        }
        guard viewModel.canAdjust, window != nil, !isHiddenOrHasHiddenAncestor else { return }
        microphonePicker.closePicker()
        let content = GenerationAdjustmentPopoverView()
        let controller = NSViewController()
        controller.view = content
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = controller
        popover.contentSize = content.fittingSize
        adjustmentPopover = popover
        popover.show(relativeTo: adjustmentButton.bounds, of: adjustmentButton, preferredEdge: .maxY)
    }
}
