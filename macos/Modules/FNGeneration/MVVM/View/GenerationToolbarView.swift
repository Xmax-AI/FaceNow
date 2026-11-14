//
//  GenerationToolbarView.swift
//  FaceNow
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

    /// Opens the centered live translation configuration.
    var onConfigureTranslation: (() -> Void)?

    /// Lets the header place statistics at the start of the generation controls.
    var statisticsControl: NSView { statisticsButton }

    /// Lets the header place interpolation before the other result controls.
    var interpolationControl: ToolbarButton { interpolationButton }

    /// Lets the header place beauty after interpolation.
    var beautyControl: ToolbarButton { beautyButton }

    /// Lets the header place live translation before the credit capsule.
    var translationControl: ToolbarButton { translationButton }

    /// The generation state and commands represented by this toolbar.
    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    /// Toggles statistics visibility without stopping metric collection.
    private lazy var statisticsButton: ToolbarButton = {
        let view = ToolbarButton(
            content: .icon(.vector(.statistics), accessibilityLabel: GenerationStrings.controlsShowStatistics),
            role: .toggle,
            tone: .accent
        )
        view.onClick = { [weak self] in self?.generationRepo.statisticsVisible.toggle() }
        return view
    }()

    /// Toggles SDK frame interpolation and displays its pending state.
    private lazy var interpolationButton: ToolbarButton = {
        let view = ToolbarButton(
            content: .labeled(GenerationStrings.controls2x, icon: .vector(.lightning)),
            role: .toggle,
            tone: .warm
        )
        view.setAccessibilityLabel(GenerationStrings.controlsFrameInterpolation)
        view.onClick = { [weak self] in
            Task { [weak self] in await self?.generationRepo.toggleInterpolation() }
        }
        return view
    }()

    /// Opens result beauty controls without changing generation or camera input.
    private lazy var beautyButton: ToolbarButton = {
        let view = ToolbarButton(
            content: .labeled(GenerationStrings.beauty, icon: .system("sparkles")),
            role: .toggle,
            tone: .warm
        )
        view.onClick = { [weak self] in self?.onToggleBeauty?() }
        return view
    }()

    /// Opens the live translation dialog and reflects the current capture state.
    private lazy var translationButton: ToolbarButton = {
        let view = ToolbarButton(
            content: .labeled(GenerationStrings.translation, icon: .system("captions.bubble")),
            role: .toggle,
            tone: .warm
        )
        view.onClick = { [weak self] in self?.onConfigureTranslation?() }
        return view
    }()

    /// The passive elapsed-session label using the same proportional font as the toolbar.
    private lazy var elapsed: ToolbarButton = {
        let view = ToolbarButton(content: .text("00:00"), role: .status)
        return view
    }()

    /// Closes the active session and reflects asynchronous cleanup.
    private lazy var stopButton: ToolbarButton = {
        let view = ToolbarButton(
            content: .labeled(GenerationStrings.controlsStopSession, icon: .vector(.stop)),
            tone: .danger
        )
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
                make.width.equalTo(button.preferredWidth)
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

    /// The complete action row width including the gaps between controls.
    var preferredWidth: CGFloat {
        elapsed.preferredWidth + ToolbarControlMetrics.spacing + stopButton.preferredWidth
    }

    /// Applies the latest generation state without replacing controls.
    func update() {
        let previousWidth = preferredWidth
        let includesTranslation = GenerationRepository.isLiveTranslationAvailable
        let previousTranslationWidth = includesTranslation ? translationButton.preferredWidth : 0
        beautyButton.isSelected = generationRepo.beautyEnabled
        beautyButton.isEnabled = generationRepo.sessionActive && !generationRepo.isClosing
        beautyButton.toolTip = GenerationStrings.beautyDescription
        beautyButton.setAccessibilityValue(generationRepo.beautyEnabled ? GenerationStrings.on : GenerationStrings.off)
        statisticsButton.isSelected = generationRepo.statisticsVisible
        statisticsButton.toolTip =
            generationRepo.statisticsVisible
            ? GenerationStrings.controlsHideStatisticsCollectionAndLoggingContinue
            : GenerationStrings.controlsShowStatistics
        statisticsButton.setAccessibilityValue(
            generationRepo.statisticsVisible ? GenerationStrings.on : GenerationStrings.off
        )
        interpolationButton.isSelected = generationRepo.interpolationEnabled
        interpolationButton.isLoading = generationRepo.interpolationSwitching
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
        if includesTranslation { updateTranslation() }
        let stopTitle =
            generationRepo.isClosing ? GenerationStrings.controlsStopping : GenerationStrings.controlsStopSession
        stopButton.content = .labeled(stopTitle, icon: .vector(.stop))
        stopButton.isLoading = generationRepo.isClosing
        stopButton.isEnabled = !generationRepo.isClosing
        updateElapsed()
        needsLayout = true
        if preferredWidth != previousWidth || (includesTranslation && translationButton.preferredWidth != previousTranslationWidth) {
            onWidthChange?()
        }
    }

    /// Shows setup progress while keeping the configuration entry available.
    private func updateTranslation() {
        let state = generationRepo.translationState
        translationButton.isEnabled = generationRepo.sessionActive && !generationRepo.isClosing
        translationButton.isSelected = state != .off
        translationButton.content = .labeled(
            state == .downloadingLanguages ? GenerationStrings.translationDownloadingLanguages : GenerationStrings.translation,
            icon: .system("captions.bubble")
        )
        let status = GenerationTranslationViewModel.status(for: generationRepo).detail
        translationButton.isLoading = state == .preparing || state == .waitingForMicrophone || state == .downloadingLanguages
        translationButton.toolTip = status
        translationButton.setAccessibilityValue(status)
    }

    /// Places the controls within the header-provided action row.
    override func layout() {
        for button in controls {
            button.snp.updateConstraints { make in make.width.equalTo(button.preferredWidth) }
        }
        super.layout()
    }

    /// Refreshes the elapsed-session label using the current start time.
    private func updateElapsed() {
        let seconds = max(0, Int(Date().timeIntervalSince(generationRepo.sessionStartedAt ?? Date())))
        let title = String(
            format: "%02d:%02d",
            seconds / 60,
            seconds % 60
        )
        elapsed.content = .text(title)
    }

}
