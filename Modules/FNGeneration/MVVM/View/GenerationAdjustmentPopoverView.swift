//
//  GenerationAdjustmentPopoverView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import Combine
import Factory
import SnapKit
import XmaxSDK

/// Presents local monitoring volume and the existing generated-result beauty settings.
@MainActor
final class GenerationAdjustmentPopoverView: Canvas {

    /// Owns playback volume, saved beauty options, and SDK operations.
    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    /// Refreshes the card after shared repository publications.
    private var observation: AnyCancellable?

    /// Serializes monitoring changes while keeping only the latest pending slider value.
    private var volumeTask: Task<Void, Never>?

    /// The next requested local monitoring volume, normalized to zero through one.
    private var pendingVolume: Float?

    /// Keeps an in-flight monitoring value visible until its SDK operation completes.
    private var applyingVolume: Float?

    /// The existing result strengths and their writable option fields.
    private static let settings: [(String, WritableKeyPath<RealtimeVideoBeautyOptions, Float>)] = [
        (GenerationStrings.beautySmoothness, \.smoothness),
        (GenerationStrings.beautyLightening, \.lightening),
        (GenerationStrings.beautySharpness, \.sharpness),
        (GenerationStrings.beautyRedness, \.redness),
    ]

    /// Reserves one measured title column for monitoring and every result strength.
    private let labelWidth: CGFloat = {
        let titles = [GenerationStrings.monitoringVolume] + GenerationAdjustmentPopoverView.settings.map(\.0)
        return ceil(titles.map { Typography.size($0, font: .systemFont(ofSize: 13)).width }.max() ?? 0)
    }()

    /// Names the settings card without changing audio or effect state when it opens.
    private lazy var heading: NSTextField = {
        let view = NSTextField(labelWithString: GenerationStrings.audioVideoAdjustments)
        view.font = .systemFont(ofSize: 18, weight: .semibold)
        view.textColor = Palette.softText
        return view
    }()

    /// Adjusts only local monitoring, independently of virtual microphone output.
    private lazy var volumeRow: GenerationAdjustmentSliderRow = {
        let view = GenerationAdjustmentSliderRow(title: GenerationStrings.monitoringVolume, labelWidth: labelWidth)
        view.toolTip = GenerationStrings.monitoringVolumeDescription
        view.onChange = { [weak self] value in self?.setMonitoringVolume(value) }
        return view
    }()

    /// Separates the audio and video sections of the card.
    private lazy var separator: Canvas = {
        let view = Canvas(color: Palette.border)
        return view
    }()

    /// Names the existing generated-result effect.
    private lazy var beautyLabel: NSTextField = {
        let view = NSTextField(labelWithString: GenerationStrings.beauty)
        view.font = .systemFont(ofSize: 13, weight: .semibold)
        view.textColor = Palette.softText
        return view
    }()

    /// Uses the shared animated button appearance for explicit effect enablement.
    private lazy var beautyToggle: ToolbarButton = {
        let view = ToolbarButton(style: .statistics)
        view.centersTitleVisually = true
        view.showsShadow = false
        view.setAccessibilityRole(.checkBox)
        view.setAccessibilityLabel(GenerationStrings.beauty)
        view.onClick = { [weak self] in
            guard let self else { return }
            self.generationRepo.setBeautyEnabled(!self.generationRepo.beautyEnabled)
        }
        return view
    }()

    /// Reuses saved normalized strengths and the repository's debounced SDK application.
    private lazy var beautyRows: [(WritableKeyPath<RealtimeVideoBeautyOptions, Float>, GenerationAdjustmentSliderRow)] =
        {
            Self.settings.map { title, key in
                let view = GenerationAdjustmentSliderRow(title: title, labelWidth: labelWidth)
                view.onChange = { [weak self] value in
                    guard let self, self.generationRepo.beautyEnabled, !self.generationRepo.isClosing else { return }
                    var options = self.generationRepo.beautyOptions
                    options[keyPath: key] = value
                    self.generationRepo.setBeautyOptions(options)
                }
                return (key, view)
            }
        }()

    /// Installs a compact card whose slider titles, tracks, and values share columns.
    init() {
        super.init(color: .white)
        [heading, volumeRow, separator, beautyLabel, beautyToggle].forEach(addSubview)
        beautyRows.forEach { addSubview($0.1) }
        snp.makeConstraints { make in make.width.equalTo(360) }
        heading.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(20)
        }
        volumeRow.snp.makeConstraints { make in
            make.top.equalTo(heading.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(20)
            make.height.equalTo(32)
        }
        separator.snp.makeConstraints { make in
            make.top.equalTo(volumeRow.snp.bottom).offset(14)
            make.leading.trailing.equalTo(volumeRow)
            make.height.equalTo(1)
        }
        beautyToggle.snp.makeConstraints { make in
            make.top.equalTo(separator.snp.bottom).offset(14)
            make.trailing.equalTo(volumeRow)
            make.width.equalTo(
                max(
                    beautyToggle.preferredWidth(for: GenerationStrings.on),
                    beautyToggle.preferredWidth(for: GenerationStrings.off)
                )
            )
            make.height.equalTo(28)
        }
        beautyLabel.snp.makeConstraints { make in
            make.leading.equalTo(volumeRow)
            make.centerY.equalTo(beautyToggle)
            make.trailing.lessThanOrEqualTo(beautyToggle.snp.leading).offset(-12)
        }
        var previous: NSView = beautyToggle
        for (_, row) in beautyRows {
            row.snp.makeConstraints { make in
                make.top.equalTo(previous.snp.bottom).offset(8)
                make.leading.trailing.equalTo(volumeRow)
                make.height.equalTo(28)
            }
            previous = row
        }
        previous.snp.makeConstraints { make in make.bottom.equalToSuperview().inset(20) }
        observation = generationRepo.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.update() }
        }
        update()
    }

    /// Storyboard decoding is unsupported for this native settings card.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Cancels pending view-owned slider work when the popover closes.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            volumeTask?.cancel()
            pendingVolume = nil
        }
    }

    /// Reflects shared values without replacing controls or applying settings during presentation.
    private func update() {
        let enabled = generationRepo.sessionActive && !generationRepo.isClosing
        volumeRow.update(
            value: pendingVolume ?? applyingVolume ?? generationRepo.remoteAudioVolume,
            enabled: enabled
        )
        beautyToggle.title = generationRepo.beautyEnabled ? GenerationStrings.on : GenerationStrings.off
        beautyToggle.selected = generationRepo.beautyEnabled
        beautyToggle.isEnabled = enabled
        beautyToggle.setAccessibilityValue(generationRepo.beautyEnabled)
        for (key, row) in beautyRows {
            row.update(
                value: generationRepo.beautyOptions[keyPath: key],
                enabled: enabled && generationRepo.beautyEnabled
            )
        }
    }

    /// Coalesces continuous user edits into one in-flight SDK volume operation.
    private func setMonitoringVolume(
        _ value: Float
    ) {
        guard generationRepo.sessionActive, !generationRepo.isClosing else { return }
        pendingVolume = value
        guard volumeTask == nil else { return }
        volumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.volumeTask = nil
                self.applyingVolume = nil
                self.update()
            }
            while !Task.isCancelled, let next = self.pendingVolume {
                self.pendingVolume = nil
                self.applyingVolume = next
                await self.generationRepo.setRemoteAudioVolume(next)
            }
        }
    }
}

/// Keeps slider titles, tracks, and proportional percentage labels aligned across settings.
@MainActor
private final class GenerationAdjustmentSliderRow: Canvas {

    /// Delivers only user changes, normalized to zero through one.
    var onChange: ((Float) -> Void)?

    /// The fixed-width title column measured from all localized setting names.
    private lazy var titleLabel: NSTextField = {
        let view = NSTextField(labelWithString: "")
        view.font = .systemFont(ofSize: 13)
        view.textColor = Palette.softText
        return view
    }()

    /// Uses a native slider for keyboard, pointer, and accessibility interaction.
    private lazy var slider: NSSlider = {
        let view = NSSlider()
        view.minValue = 0
        view.maxValue = 100
        view.isContinuous = true
        view.controlSize = .small
        view.target = self
        view.action = #selector(sliderChanged)
        return view
    }()

    /// Displays the current setting without fixed-width numeric typography.
    private lazy var valueLabel: NSTextField = {
        let view = NSTextField(labelWithString: "")
        view.font = .systemFont(ofSize: 13)
        view.textColor = Palette.secondary
        view.alignment = .right
        return view
    }()

    /// Installs shared column widths with the value aligned to the title baseline.
    init(
        title: String,
        labelWidth: CGFloat
    ) {
        super.init()
        titleLabel.stringValue = title
        slider.setAccessibilityLabel(title)
        [titleLabel, slider, valueLabel].forEach(addSubview)
        titleLabel.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
            make.width.equalTo(labelWidth)
        }
        valueLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.lastBaseline.equalTo(titleLabel.snp.lastBaseline)
            make.width.equalTo(40)
        }
        slider.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel.snp.trailing).offset(8)
            make.trailing.equalTo(valueLabel.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
        }
    }

    /// Storyboard decoding is unsupported for this native slider row.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Updates values while sharing the standard disabled-opacity transition.
    func update(
        value: Float,
        enabled: Bool
    ) {
        let percent = Int((value * 100).rounded())
        slider.doubleValue = Double(percent)
        valueLabel.stringValue = GenerationStrings.percentage(value: percent)
        slider.isEnabled = enabled
        ControlMotion.setOpacity(enabled ? 1 : 0.45, on: self)
    }

    /// Publishes continuous edits while retaining the visible integer percentage.
    @objc private func sliderChanged() {
        let percent = Int(slider.doubleValue.rounded())
        valueLabel.stringValue = GenerationStrings.percentage(value: percent)
        onChange?(Float(percent) / 100)
    }
}
