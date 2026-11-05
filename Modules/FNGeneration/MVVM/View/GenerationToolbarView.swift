//
//  GenerationToolbarView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Factory
import AppKit
import SnapKit

/// Owns generation actions, statistics visibility, and elapsed time.
@MainActor
final class GenerationToolbarView: Canvas {

    /// Requests parent layout only when a control's measured width changes.
    var onWidthChange: (() -> Void)?

    /// Requests the workspace-owned result overlay without retaining a separate popover.
    var onToggleBeauty: (() -> Void)?

    /// Lets the header place statistics at the start of the generation controls.
    var statisticsControl: NSView { statisticsButton }

    /// Lets the header place interpolation before beauty and the credit capsule.
    var interpolationControl: ToolbarButton { interpolationButton }

    /// Lets the header place beauty immediately before the separately owned credit capsule.
    var beautyControl: ToolbarButton { beautyButton }

    /// The generation state and commands represented by this toolbar.
    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    /// Toggles statistics visibility without stopping metric collection.
    private lazy var statisticsButton: ToolbarButton = {
        let view = ToolbarButton(
            icon: .statistics,
            style: .statistics,
            shape: .circle
        )
        view.font = .systemFont(ofSize: ToolbarControlMetrics.fontSize, weight: .semibold)
        view.setAccessibilityLabel(GenerationStrings.controlsShowStatistics)
        view.onClick = { [weak self] in self?.generationRepo.statisticsVisible.toggle() }
        return view
    }()

    /// Toggles SDK frame interpolation and displays its pending state.
    private lazy var interpolationButton: ToolbarButton = {
        let view = ToolbarButton(
            GenerationStrings.controls2x,
            icon: .lightning,
            style: .interpolation
        )
        view.font = .systemFont(ofSize: ToolbarControlMetrics.fontSize, weight: .semibold)
        view.setAccessibilityLabel(GenerationStrings.controlsFrameInterpolation)
        view.onClick = { [weak self] in
            Task { [weak self] in await self?.generationRepo.toggleInterpolation() }
        }
        return view
    }()

    /// Opens result beauty controls without changing generation or camera input.
    private lazy var beautyButton: ToolbarButton = {
        let view = ToolbarButton(
            GenerationStrings.beauty,
            style: .interpolation
        )
        view.symbolName = "sparkles"
        view.font = .systemFont(ofSize: ToolbarControlMetrics.fontSize, weight: .semibold)
        view.setAccessibilityLabel(GenerationStrings.beauty)
        view.onClick = { [weak self] in self?.onToggleBeauty?() }
        return view
    }()

    /// The passive elapsed-session label using the same proportional font as the toolbar.
    private lazy var elapsed: ToolbarButton = {
        let view = ToolbarButton("00:00")
        view.font = .systemFont(ofSize: ToolbarControlMetrics.fontSize, weight: .medium)
        view.passive = true
        view.isEnabled = false
        return view
    }()

    /// Closes the active session and reflects asynchronous cleanup.
    private lazy var stopButton: ToolbarButton = {
        let view = ToolbarButton(
            GenerationStrings.controlsStopSession,
            icon: .stop,
            style: .destructive
        )
        view.font = .systemFont(ofSize: ToolbarControlMetrics.fontSize, weight: .semibold)
        view.onClick = { [weak self] in Task { [weak self] in await self?.generationRepo.close() } }
        return view
    }()

    /// Creates persistent controls and binds their session actions.
    init() {
        super.init()
        controls.forEach(addSubview)
        var previous: ToolbarButton?
        for button in controls {
            button.snp.makeConstraints { make in
                make.top.bottom.equalToSuperview()
                if button.shape == .capsule {
                    make.width.equalTo(preferredWidth(for: button))
                }
                if let previous {
                    make.leading.equalTo(previous.snp.trailing).offset(ToolbarControlMetrics.spacing)
                } else {
                    make.leading.equalToSuperview()
                }
            }
            previous = button
        }
    }

    /// Storyboard decoding is unsupported for this programmatic view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// The persistent controls shared by measurement and constraint updates.
    private var controls: [ToolbarButton] {
        [elapsed, stopButton]
    }

    /// Reserves a stable stop-action width using the component's own label measurement.
    private func preferredWidth(
        for button: ToolbarButton
    ) -> CGFloat {
        if button === stopButton {
            return max(
                button.preferredWidth(for: GenerationStrings.controlsStopSession),
                button.preferredWidth(for: GenerationStrings.controlsStopping)
            )
        }
        return button.preferredWidth
    }

    /// The complete action row width including the gaps between controls.
    func preferredWidth(
        controlHeight: CGFloat
    ) -> CGFloat {
        controls.reduce(CGFloat(0)) { width, button in
            width
                + (button.shape == .circle
                    ? button.preferredWidth(controlHeight: controlHeight) : preferredWidth(for: button))
        } + CGFloat(controls.count - 1) * ToolbarControlMetrics.spacing
    }

    /// Applies the latest generation state without replacing controls.
    func update() {
        beautyButton.selected = generationRepo.beautyEnabled
        beautyButton.isEnabled = generationRepo.sessionActive && !generationRepo.isClosing
        beautyButton.toolTip = GenerationStrings.beautyDescription
        beautyButton.setAccessibilityValue(generationRepo.beautyEnabled ? GenerationStrings.on : GenerationStrings.off)
        statisticsButton.selected = generationRepo.statisticsVisible
        statisticsButton.toolTip =
            generationRepo.statisticsVisible
            ? GenerationStrings.controlsHideStatisticsCollectionAndLoggingContinue
            : GenerationStrings.controlsShowStatistics
        statisticsButton.setAccessibilityValue(
            generationRepo.statisticsVisible ? GenerationStrings.on : GenerationStrings.off
        )
        interpolationButton.selected = generationRepo.interpolationEnabled
        interpolationButton.loading = generationRepo.interpolationSwitching
        interpolationButton.isEnabled = !generationRepo.isBusy
        interpolationButton.toolTip =
            generationRepo.interpolationSwitching
            ? GenerationStrings.controlsSwitchingFrameInterpolation
            : generationRepo.interpolationEnabled
                ? GenerationStrings.controls2FrameInterpolationIsOnClickToTurnOff
                : GenerationStrings.controlsFrameInterpolationIsOffClickToTurnOn
        interpolationButton.setAccessibilityValue(
            generationRepo.interpolationSwitching
                ? GenerationStrings.controlsSwitching
                : generationRepo.interpolationEnabled ? GenerationStrings.on : GenerationStrings.off
        )
        stopButton.title =
            generationRepo.isClosing ? GenerationStrings.controlsStopping : GenerationStrings.controlsStopSession
        stopButton.loading = generationRepo.isClosing
        stopButton.isEnabled = !generationRepo.isClosing
        updateElapsed()
        needsLayout = true

    }

    /// Places the controls within the header-provided action row.
    override func layout() {
        for button in controls where button.shape == .capsule {
            button.snp.updateConstraints { make in make.width.equalTo(preferredWidth(for: button)) }
        }
        super.layout()
    }

    /// Refreshes elapsed time and requests parent layout when its measured width changes.
    private func updateElapsed() {
        let seconds = max(0, Int(Date().timeIntervalSince(generationRepo.sessionStartedAt ?? Date())))
        let title = String(
            format: "%02d:%02d",
            seconds / 60,
            seconds % 60
        )
        if elapsed.title != title {
            let previousWidth = elapsed.preferredWidth
            elapsed.title = title
            if previousWidth != elapsed.preferredWidth { onWidthChange?() }
        }
    }

}
