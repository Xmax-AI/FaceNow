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

/// Owns the generation actions, elapsed time, and serialized playback-volume edits.
@MainActor
final class GenerationToolbarView: Canvas {

    /// Requests parent layout only when a control's measured width changes.
    var onWidthChange: (() -> Void)?

    /// The generation state and commands represented by this toolbar.
    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    /// Toggles statistics visibility without stopping metric collection.
    private lazy var statisticsButton: Button = {
        let view = Button(
            icon: .statistics,
            style: .statistics
        )
        view.font = Typography.font(
            size: 13,
            weight: .semibold
        )
        view.setAccessibilityLabel("Show statistics")
        view.onClick = { [weak self] in self?.generationRepo.statisticsVisible.toggle() }
        return view
    }()

    /// Opens the remote generated-audio playback control.
    private lazy var volumeButton: Button = {
        let view = Button(
            icon: .muted,
            style: .volume
        )
        view.font = Typography.font(
            size: 13,
            weight: .semibold
        )
        view.toolTip = "Adjust remote playback volume"
        view.setAccessibilityLabel("Remote volume")
        view.onClick = { [weak self] in self?.showVolume() }
        return view
    }()

    /// Toggles SDK frame interpolation and displays its pending state.
    private lazy var interpolationButton: Button = {
        let view = Button(
            "2x",
            icon: .lightning,
            style: .interpolation
        )
        view.font = Typography.font(
            size: 13,
            weight: .semibold
        )
        view.iconSize = 15
        view.iconSpacing = 3
        view.leadingPadding = 12
        view.trailingPadding = 15
        view.setAccessibilityLabel("Frame interpolation")
        view.onClick = { [weak self] in
            Task { [weak self] in await self?.generationRepo.toggleInterpolation() }
        }
        return view
    }()

    /// The passive elapsed-session label with stable monospaced digits.
    private lazy var elapsed: Button = {
        let view = Button("00:00")
        view.font = Typography.font(
            size: 13,
            weight: .medium,
            monospacedDigits: true
        )
        view.passive = true
        view.isEnabled = false
        return view
    }()

    /// Closes the active session and reflects asynchronous cleanup.
    private lazy var stopButton: Button = {
        let view = Button(
            "Stop Session",
            icon: .stop,
            style: .destructive
        )
        view.font = Typography.font(
            size: 13,
            weight: .semibold
        )
        view.iconSize = 12
        view.iconSpacing = 7
        view.leadingPadding = 16
        view.trailingPadding = 16
        view.onClick = { [weak self] in Task { [weak self] in await self?.generationRepo.close() } }
        return view
    }()

    /// The continuous native remote-playback volume editor.
    private lazy var volumeSlider: NSSlider = {
        let view = NSSlider(
            value: 0,
            minValue: 0,
            maxValue: 1,
            target: nil,
            action: nil
        )
        view.target = self
        view.action = #selector(volumeChanged)
        view.isContinuous = true
        view.setAccessibilityLabel("Remote volume")
        return view
    }()

    /// The formatted mute state or playback-volume percentage.
    private lazy var volumeValue: NSTextField = {
        let view = makeLabel(
            "Muted",
            size: 12,
            color: Palette.secondary
        )
        return view
    }()

    /// The transient popover currently owned by this component.
    private var popover: NSPopover?

    /// Serializes slider changes so only the latest pending volume is retained.
    private var volumeTask: Task<Void, Never>?

    /// The latest slider value waiting for the active playback update.
    private var pendingVolume: Float?

    /// Creates persistent controls and binds their session actions.
    init() {
        super.init()
        [statisticsButton, volumeButton, interpolationButton, elapsed, stopButton].forEach(addSubview)
        var previous: Button?
        for (button, width) in controls {
            button.snp.makeConstraints { make in
                make.top.equalToSuperview()
                make.height.equalTo(36)
                make.width.equalTo(width)
                if let previous {
                    make.leading.equalTo(previous.snp.trailing).offset(12)
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

    /// The controls and widths used for both measurement and placement.
    private var controls: [(Button, CGFloat)] {
        let stopWidth =
            ceil(
                Typography.size(
                    "Stop Session",
                    font: stopButton.font!
                ).width
            ) + 12 + 7 + 32
        return [
            (statisticsButton, 36), (volumeButton, 36),
            (interpolationButton, interpolationButton.preferredWidth),
            (elapsed, elapsed.preferredWidth), (stopButton, stopWidth),
        ]
    }

    /// The complete action row width including the gaps between controls.
    var preferredWidth: CGFloat {
        controls.reduce(CGFloat(0)) { $0 + $1.1 } + CGFloat(controls.count - 1) * 12
    }

    /// Applies the latest generation and playback state without replacing controls.
    func update() {
        statisticsButton.selected = generationRepo.statisticsVisible
        statisticsButton.toolTip =
            generationRepo.statisticsVisible ? "Hide statistics (collection and logging continue)" : "Show statistics"
        statisticsButton.setAccessibilityValue(generationRepo.statisticsVisible ? "On" : "Off")
        volumeButton.icon =
            generationRepo.remoteAudioVolume == 0
            ? .muted : generationRepo.remoteAudioVolume > 0.5 ? .volume : .volumeLow
        volumeButton.selected = generationRepo.remoteAudioVolume > 0
        volumeButton.isEnabled = !generationRepo.isClosing
        volumeButton.setAccessibilityValue(
            generationRepo.remoteAudioVolume == 0 ? "Muted" : "\(Int(generationRepo.remoteAudioVolume * 100))%"
        )
        volumeSlider.isEnabled = !generationRepo.isClosing
        if volumeTask == nil { volumeSlider.doubleValue = Double(generationRepo.remoteAudioVolume) }
        volumeValue.stringValue =
            generationRepo.remoteAudioVolume == 0 ? "Muted" : "\(Int(generationRepo.remoteAudioVolume * 100))%"
        interpolationButton.selected = generationRepo.interpolationEnabled
        interpolationButton.loading = generationRepo.interpolationSwitching
        interpolationButton.isEnabled = !generationRepo.isBusy
        interpolationButton.toolTip =
            generationRepo.interpolationSwitching
            ? "Switching frame interpolation…"
            : generationRepo.interpolationEnabled
                ? "2× frame interpolation is on. Click to turn off" : "Frame interpolation is off. Click to turn on"
        interpolationButton.setAccessibilityValue(
            generationRepo.interpolationSwitching ? "Switching" : generationRepo.interpolationEnabled ? "On" : "Off"
        )
        stopButton.title = generationRepo.isClosing ? "Stopping…" : "Stop Session"
        stopButton.loading = generationRepo.isClosing
        stopButton.isEnabled = !generationRepo.isClosing
        updateElapsed()
        needsLayout = true

    }

    /// Places the controls within the header-provided action row.
    override func layout() {
        super.layout()
        for (button, width) in controls {
            button.snp.updateConstraints { make in make.width.equalTo(width) }
        }
    }

    /// Cancels queued volume updates and releases its popover during shutdown.
    func shutdown() {
        pendingVolume = nil
        volumeTask?.cancel()
        volumeTask = nil
        closePopover()
    }

    /// Dismisses the playback popover when the active page changes.
    func closePopover() {
        popover?.close()
        popover = nil
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

    /// Popovers use native fields and controls, keeping keyboard editing independent of session redraws.
    private func presentPopover(
        content: NSView,
        from button: NSView
    ) {
        popover?.close()
        let controller = NSViewController()
        controller.view = content
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.contentSize = content.fittingSize
        self.popover = popover
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .maxY
        )
    }

    /// Presents the retained native slider without replacing an active session.
    private func showVolume() {
        let content = Canvas()

        content.snp.makeConstraints { make in
            make.width.equalTo(244)
            make.height.equalTo(88)
        }
        let label = makeLabel("Remote volume", size: 12)
        volumeValue.alignment = .right
        [label, volumeValue, volumeSlider].forEach(content.addSubview)
        label.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().offset(14)
            make.height.equalTo(18)
            make.trailing.equalTo(volumeValue.snp.leading)
        }
        volumeValue.snp.remakeConstraints { make in
            make.trailing.equalToSuperview().inset(14)
            make.firstBaseline.equalTo(label)
            make.width.equalTo(71)
            make.height.equalTo(18)
        }
        volumeSlider.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(14)
            make.top.equalTo(label.snp.bottom).offset(14)
            make.height.equalTo(24)
        }
        presentPopover(
            content: content,
            from: volumeButton
        )
    }

    /// Queues the latest volume value while a previous SDK update is in flight.
    @objc private func volumeChanged() {
        let value = Float(volumeSlider.doubleValue)
        volumeValue.stringValue = value == 0 ? "Muted" : "\(Int(value * 100))%"
        pendingVolume = value
        guard volumeTask == nil else { return }
        volumeTask = Task { [weak self] in
            guard let self else { return }
            while let value = self.pendingVolume, !Task.isCancelled {
                self.pendingVolume = nil
                await self.generationRepo.setRemoteAudioVolume(value)
            }
            self.volumeTask = nil
            self.update()
        }
    }

}
