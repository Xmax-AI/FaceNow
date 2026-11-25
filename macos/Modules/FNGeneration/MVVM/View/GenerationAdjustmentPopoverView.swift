//
//  GenerationAdjustmentPopoverView.swift
//  FaceNow
//

import AppKit
import Combine
import SnapKit

/// Adjusts microphone echo cancellation, virtual microphone volume, and meeting output timing.
@MainActor
final class GenerationAdjustmentPopoverView: Canvas, NSTextFieldDelegate {

    /// Dismisses the workspace-owned settings popover.
    var onClose: (() -> Void)?

    /// Supplies saved timing and forwards edits to the generation-owned output scheduler.
    private let viewModel = GenerationAudioControlsViewModel()

    /// Keeps reopened and currently displayed controls aligned with the saved setting.
    private var offsetObservation: AnyCancellable?

    /// Keeps the volume control synchronized with shared output preferences.
    private var volumeObservation: AnyCancellable?

    /// Names the settings card.
    private lazy var heading: NSTextField = {
        let view = Self.label(GenerationStrings.audioVideoAdjustments, size: 22, weight: .semibold)
        return view
    }()

    /// Closes the card without changing the active generation session.
    private lazy var closeButton: Button = {
        let view = Button(style: .plain)
        view.configureForToolbar(weight: .regular)
        view.leadingPadding = 0
        view.trailingPadding = 0
        view.centersSymbolVisually = true
        view.symbolName = "xmark"
        view.iconSize = 16
        view.foregroundColor = Palette.secondary
        view.setAccessibilityLabel(GenerationStrings.adjustmentsClose)
        view.onClick = { [weak self] in self?.onClose?() }
        return view
    }()

    /// Selects the playback reference for microphone echo cancellation.
    private lazy var echoSection: GenerationEchoCancellationView = {
        let view = GenerationEchoCancellationView(settings: viewModel.echoCancellation)
        return view
    }()

    /// Names the automatic timestamp alignment underneath the manual offset.
    private lazy var automaticTitle: NSTextField = {
        let view = Self.label(GenerationStrings.automaticSync, size: 16, weight: .semibold)
        return view
    }()

    /// Groups the fixed enabled badge without making it an interactive switch.
    private lazy var enabledBadge: Canvas = {
        let view = Canvas(color: NSColor(srgbRed: 0.85, green: 0.96, blue: 0.84, alpha: 1), radius: 10)
        return view
    }()

    /// Displays the active timestamp-alignment status.
    private lazy var enabledLabel: NSTextField = {
        let view = Self.label(GenerationStrings.syncEnabled, size: 12, weight: .semibold)
        view.textColor = NSColor(srgbRed: 0.22, green: 0.65, blue: 0.16, alpha: 1)
        return view
    }()

    /// Explains automatic alignment of sound and generated video.
    private lazy var automaticDescription: NSTextField = {
        let view = Self.label(GenerationStrings.automaticSyncDescription, secondary: true)
        return view
    }()

    /// Separates automatic synchronization from the manual offset controls.
    private lazy var separator: Canvas = {
        let view = Canvas(color: Palette.border)
        return view
    }()

    /// Names the manual offset section.
    private lazy var manualTitle: NSTextField = {
        let view = Self.label(GenerationStrings.manualSyncOffset, size: 16, weight: .semibold)
        return view
    }()

    /// Explains the relationship between manual and automatic synchronization.
    private lazy var manualDescription: NSTextField = {
        let view = Self.label(GenerationStrings.manualSyncDescription, secondary: true)
        return view
    }()

    /// Edits relative meeting-output timing within minus 5000 through plus 5000 milliseconds.
    private lazy var offsetSlider: NSSlider = {
        let view = NSSlider()
        view.cell = GenerationAdjustmentSliderCell()
        view.minValue = -5000
        view.maxValue = 5000
        view.doubleValue = 0
        view.isContinuous = true
        view.target = self
        view.action = #selector(sliderChanged)
        view.setAccessibilityLabel(GenerationStrings.manualSyncOffset)
        return view
    }()

    /// Labels the earlier-audio end of the slider.
    private lazy var earlierLabel: NSTextField = {
        let view = Self.label(GenerationStrings.audioEarlier, secondary: true)
        return view
    }()

    /// Shows the signed offset directly below the slider midpoint.
    private lazy var offsetLabel: NSTextField = {
        let view = Self.label("0 ms", weight: .medium)
        view.alignment = .center
        return view
    }()

    /// Labels the later-audio end of the slider.
    private lazy var laterLabel: NSTextField = {
        let view = Self.label(GenerationStrings.audioLater, secondary: true)
        return view
    }()

    /// Names the numeric offset editor.
    private lazy var valueTitle: NSTextField = {
        let view = Self.label(GenerationStrings.syncOffsetValue, size: 14)
        return view
    }()

    /// Frames the editor and its unit as one rounded input.
    private lazy var inputContainer: Canvas = {
        let view = Canvas(color: .white, radius: 7)
        view.layer?.borderWidth = 1
        view.layer?.borderColor = Palette.border.cgColor
        return view
    }()

    /// Allows signed numeric input and normalizes it when editing ends.
    private lazy var offsetInput: NSTextField = {
        let view = NSTextField(string: "0")
        view.font = .systemFont(ofSize: 14)
        view.textColor = Palette.text
        view.alignment = .left
        view.isBordered = false
        view.drawsBackground = false
        view.focusRingType = .none
        view.delegate = self
        view.setAccessibilityLabel(GenerationStrings.syncOffsetValue)
        return view
    }()

    /// Gives the numeric editor a fixed millisecond suffix.
    private lazy var unitLabel: NSTextField = {
        let view = Self.label("ms", size: 14, secondary: true)
        return view
    }()

    /// Restores automatic alignment by clearing the additional offset.
    private lazy var resetButton: Button = {
        let view = Button(GenerationStrings.syncReset)
        view.configureForToolbar(weight: .regular)
        view.cornerRadius = 7
        view.showsShadow = false
        view.centersTitleVisually = true
        view.onClick = { [weak self] in self?.setOffset(0) }
        return view
    }()

    /// Separates output volume from the synchronization controls.
    private lazy var volumeSeparator: Canvas = {
        let view = Canvas(color: Palette.border)
        return view
    }()

    private lazy var volumeTitle: NSTextField = {
        let view = Self.label(GenerationStrings.virtualMicrophoneVolume, size: 16, weight: .semibold)
        return view
    }()

    private lazy var volumeLabel: NSTextField = {
        let view = Self.label(GenerationStrings.volumePercentage(value: 100), weight: .medium)
        view.alignment = .right
        return view
    }()

    /// Edits linear virtual microphone output gain in percent.
    private lazy var volumeSlider: NSSlider = {
        let view = NSSlider()
        view.cell = GenerationAdjustmentSliderCell()
        view.minValue = 0
        view.maxValue = viewModel.maximumVirtualMicrophonePercentage
        view.doubleValue = 100
        view.isContinuous = true
        view.target = self
        view.action = #selector(volumeChanged)
        view.setAccessibilityLabel(GenerationStrings.virtualMicrophoneVolume)
        return view
    }()

    /// Explains that live adjustments apply to meeting output.
    private lazy var footer: NSTextField = {
        let view = Self.label(GenerationStrings.syncRealtimeHint, secondary: true)
        return view
    }()

    /// Composes a content-sized card with consistent text, divider, and control insets.
    init() {
        super.init(color: .white, radius: 16)
        [
            heading, closeButton, echoSection, automaticTitle, enabledBadge, automaticDescription,
            separator,
            manualTitle, manualDescription, offsetSlider, earlierLabel, offsetLabel,
            laterLabel, valueTitle, inputContainer, resetButton,
            volumeSeparator, volumeTitle, volumeLabel, volumeSlider, footer,
        ].forEach(addSubview)
        enabledBadge.addSubview(enabledLabel)
        inputContainer.addSubview(offsetInput)
        inputContainer.addSubview(unitLabel)
        installConstraints()
        offsetObservation = viewModel.audioSyncOffsets.removeDuplicates().sink { [weak self] value in
            self?.displayOffset(value)
        }
        volumeObservation = viewModel.virtualMicrophoneVolumes.removeDuplicates().sink { [weak self] value in
            self?.displayVolume(value)
        }
    }

    /// Storyboard decoding is unsupported for this native settings card.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Uses stable constraints to match the reference card's vertical sections and shared edges.
    private func installConstraints() {
        snp.makeConstraints { make in make.width.equalTo(480) }
        heading.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(24)
            make.trailing.lessThanOrEqualTo(closeButton.snp.leading).offset(-16)
        }
        closeButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(18)
            make.centerY.equalTo(heading)
            make.size.equalTo(30)
        }
        echoSection.snp.makeConstraints { make in
            make.top.equalTo(heading.snp.bottom).offset(24)
            make.leading.trailing.equalToSuperview().inset(24)
        }
        automaticTitle.snp.makeConstraints { make in
            make.top.equalTo(echoSection.snp.bottom).offset(18)
            make.leading.equalToSuperview().inset(24)
        }
        enabledBadge.snp.makeConstraints { make in
            make.leading.greaterThanOrEqualTo(automaticTitle.snp.trailing).offset(14)
            make.centerY.equalTo(automaticTitle)
            make.trailing.equalToSuperview().inset(24)
        }
        enabledLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(9)
            make.top.bottom.equalToSuperview().inset(3)
        }
        automaticDescription.snp.makeConstraints { make in
            make.top.equalTo(automaticTitle.snp.bottom).offset(6)
            make.leading.trailing.equalToSuperview().inset(24)
        }
        separator.snp.makeConstraints { make in
            make.top.equalTo(automaticDescription.snp.bottom).offset(18)
            make.leading.trailing.equalTo(automaticDescription)
            make.height.equalTo(1)
        }
        manualTitle.snp.makeConstraints { make in
            make.top.equalTo(separator.snp.bottom).offset(18)
            make.leading.trailing.equalTo(automaticDescription)
        }
        manualDescription.snp.makeConstraints { make in
            make.top.equalTo(manualTitle.snp.bottom).offset(6)
            make.leading.trailing.equalTo(automaticDescription)
        }
        offsetSlider.snp.makeConstraints { make in
            make.top.equalTo(manualDescription.snp.bottom).offset(20)
            make.leading.trailing.equalTo(automaticDescription)
            make.height.equalTo(26)
        }
        earlierLabel.snp.makeConstraints { make in
            make.top.equalTo(offsetSlider.snp.bottom).offset(4)
            make.leading.equalToSuperview().inset(24)
        }
        offsetLabel.snp.makeConstraints { make in
            make.top.equalTo(earlierLabel.snp.top)
            make.centerX.equalToSuperview()
        }
        laterLabel.snp.makeConstraints { make in
            make.top.equalTo(earlierLabel.snp.top)
            make.trailing.equalToSuperview().inset(24)
        }
        valueTitle.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(24)
            make.centerY.equalTo(inputContainer)
        }
        inputContainer.snp.makeConstraints { make in
            make.top.equalTo(earlierLabel.snp.bottom).offset(24)
            make.leading.equalTo(valueTitle.snp.trailing).offset(20)
            make.width.equalTo(126)
            make.height.equalTo(32)
        }
        offsetInput.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(12)
            make.centerY.equalToSuperview()
            make.trailing.equalTo(unitLabel.snp.leading).offset(-8)
        }
        unitLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(12)
            make.centerY.equalTo(offsetInput.snp.centerY)
        }
        resetButton.snp.makeConstraints { make in
            make.leading.equalTo(inputContainer.snp.trailing).offset(18)
            make.centerY.height.equalTo(inputContainer)
            make.width.equalTo(82)
            make.trailing.lessThanOrEqualToSuperview().inset(24)
        }
        volumeSeparator.snp.makeConstraints { make in
            make.top.equalTo(inputContainer.snp.bottom).offset(24)
            make.leading.trailing.equalTo(automaticDescription)
            make.height.equalTo(1)
        }
        volumeTitle.snp.makeConstraints { make in
            make.top.equalTo(volumeSeparator.snp.bottom).offset(18)
            make.leading.equalTo(automaticDescription)
            make.trailing.lessThanOrEqualTo(volumeLabel.snp.leading).offset(-16)
        }
        volumeLabel.snp.makeConstraints { make in
            make.centerY.equalTo(volumeTitle)
            make.trailing.equalTo(automaticDescription)
        }
        volumeSlider.snp.makeConstraints { make in
            make.top.equalTo(volumeTitle.snp.bottom).offset(12)
            make.leading.trailing.equalTo(automaticDescription)
            make.height.equalTo(26)
        }
        footer.snp.makeConstraints { make in
            make.top.equalTo(volumeSlider.snp.bottom).offset(18)
            make.leading.trailing.equalTo(automaticDescription)
            make.bottom.equalToSuperview().inset(24)
        }
    }

    /// Creates a generation-page label using native proportional system typography.
    private static func label(
        _ text: String,
        size: CGFloat = 13,
        weight: NSFont.Weight = .regular,
        secondary: Bool = false
    ) -> NSTextField {
        let view = NSTextField(labelWithString: text)
        view.font = .systemFont(ofSize: size, weight: weight)
        view.textColor = secondary ? Palette.secondary : Palette.text
        view.alignment = .left
        return view
    }

    /// Saves a bounded offset and normalizes all three visible representations.
    private func setOffset(
        _ value: Int
    ) {
        let offset = min(5000, max(-5000, value))
        viewModel.setAudioSyncOffset(offset)
        displayOffset(viewModel.audioSyncOffsetMilliseconds)
        offsetInput.stringValue = String(viewModel.audioSyncOffsetMilliseconds)
    }

    /// Reflects saved values without overwriting an in-progress numeric edit.
    private func displayOffset(
        _ value: Int
    ) {
        offsetSlider.integerValue = value
        if offsetInput.currentEditor() == nil { offsetInput.stringValue = String(value) }
        offsetLabel.stringValue = GenerationStrings.syncOffsetMilliseconds(value: value)
    }

    /// Reflects saved gain as a whole percentage without changing the audio setting.
    private func displayVolume(
        _ volume: Float
    ) {
        let percent = Int((volume * 100).rounded())
        volumeSlider.integerValue = percent
        volumeLabel.stringValue = GenerationStrings.volumePercentage(value: percent)
        volumeSlider.setAccessibilityValueDescription(volumeLabel.stringValue)
    }

    @objc private func volumeChanged() {
        viewModel.setVirtualMicrophoneVolume(Float(volumeSlider.doubleValue.rounded()) / 100)
    }

    /// Applies pointer and keyboard slider edits to meeting output.
    @objc private func sliderChanged() {
        setOffset(Int(offsetSlider.doubleValue.rounded()))
    }

    /// Applies valid numeric edits while allowing a minus sign during typing.
    func controlTextDidChange(
        _ notification: Notification
    ) {
        guard let value = Int(offsetInput.stringValue), (-5000...5000).contains(value) else { return }
        viewModel.setAudioSyncOffset(value)
    }

    /// Restores a valid bounded setting when numeric editing completes.
    func controlTextDidEndEditing(
        _ notification: Notification
    ) {
        setOffset(Int(offsetInput.stringValue) ?? viewModel.audioSyncOffsetMilliseconds)
    }
}

/// Presents the echo filter and its reference device in the audio settings card.
@MainActor
private final class GenerationEchoCancellationView: NSView {

    private let settings: PlaybackEchoCancellation
    private var observation: AnyCancellable?

    private lazy var toggle: NSSwitch = {
        let view = NSSwitch()
        view.setAccessibilityLabel(GenerationStrings.echoCancellation)
        view.target = self
        view.action = #selector(changeEnabled)
        return view
    }()

    private lazy var devicePicker: NSPopUpButton = {
        let view = NSPopUpButton(frame: .zero, pullsDown: false)
        view.setAccessibilityLabel(GenerationStrings.echoPlaybackDevice)
        view.target = self
        view.action = #selector(changeDevice)
        view.autoenablesItems = false
        return view
    }()

    private lazy var statusLabel: NSTextField = {
        let view = NSTextField(wrappingLabelWithString: "")
        view.textColor = Palette.secondary
        view.font = .systemFont(ofSize: 13)
        view.maximumNumberOfLines = 0
        return view
    }()

    init(
        settings: PlaybackEchoCancellation
    ) {
        self.settings = settings
        super.init(frame: .zero)

        let title = NSTextField(labelWithString: GenerationStrings.echoCancellation)
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = Palette.text
        let deviceLabel = NSTextField(labelWithString: GenerationStrings.echoPlaybackDevice)
        deviceLabel.textColor = Palette.secondary
        let divider = Canvas(color: Palette.border)
        [title, toggle, deviceLabel, devicePicker, statusLabel, divider].forEach(addSubview)

        toggle.snp.makeConstraints { make in make.top.trailing.equalToSuperview() }
        title.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.centerY.equalTo(toggle)
        }
        devicePicker.snp.makeConstraints { make in
            make.top.equalTo(toggle.snp.bottom).offset(9)
            make.trailing.equalToSuperview()
            make.width.equalTo(246)
        }
        deviceLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.centerY.equalTo(devicePicker)
            make.trailing.lessThanOrEqualTo(devicePicker.snp.leading).offset(-10)
        }
        statusLabel.snp.makeConstraints { make in
            make.top.equalTo(devicePicker.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview()
        }
        divider.snp.makeConstraints { make in
            make.top.equalTo(statusLabel.snp.bottom).offset(16)
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(1)
        }

        observation = settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    private func refresh() {
        toggle.isEnabled = settings.isSupported
        toggle.state = settings.enabled && settings.isSupported ? .on : .off
        devicePicker.isEnabled = settings.isSupported
        devicePicker.removeAllItems()
        devicePicker.addItem(withTitle: GenerationStrings.echoFollowSystem)
        var titles = Set([GenerationStrings.echoFollowSystem, GenerationStrings.echoDeviceUnavailable])
        for device in settings.devices {
            var title = device.name
            var suffix = 2
            while !titles.insert(title).inserted {
                title = "\(device.name) (\(suffix))"
                suffix += 1
            }
            devicePicker.addItem(withTitle: title)
            devicePicker.lastItem?.representedObject = device.uid
        }
        devicePicker.selectItem(at: 0)
        if let uid = settings.deviceUID {
            if let item = devicePicker.itemArray.first(where: { ($0.representedObject as? String) == uid }) {
                devicePicker.select(item)
            } else {
                devicePicker.addItem(withTitle: GenerationStrings.echoDeviceUnavailable)
                let unavailableItem = devicePicker.lastItem
                unavailableItem?.isEnabled = false
                devicePicker.select(unavailableItem)
            }
        }
        statusLabel.stringValue = switch settings.status {
        case .off: GenerationStrings.echoOff
        case .waitingForMicrophone: GenerationStrings.echoWaiting
        case .starting: GenerationStrings.echoStarting
        case .waitingForReference: GenerationStrings.echoWaitingForReference
        case .listening: GenerationStrings.echoListening
        case .noDevice: GenerationStrings.echoNoDevice
        case .unavailable: GenerationStrings.echoUnavailable
        case .failed: GenerationStrings.echoFailed
        }
    }

    @objc private func changeEnabled() {
        settings.setEnabled(toggle.state == .on)
    }

    @objc private func changeDevice() {
        settings.selectDevice(devicePicker.selectedItem?.representedObject as? String)
    }
}

/// Draws the reference slider's blue track and outlined white knob using native slider tracking.
@MainActor
private final class GenerationAdjustmentSliderCell: NSSliderCell {

    /// Draws the inactive track and the blue segment preceding the current value.
    override func drawBar(
        inside rect: NSRect,
        flipped: Bool
    ) {
        let track = NSRect(x: rect.minX, y: rect.midY - 3, width: rect.width, height: 6)
        NSColor(srgbRed: 0.84, green: 0.85, blue: 0.89, alpha: 1).setFill()
        NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
        let progress = CGFloat((doubleValue - minValue) / (maxValue - minValue))
        let filled = NSRect(x: track.minX, y: track.minY, width: track.width * progress, height: track.height)
        Palette.accent.setFill()
        NSBezierPath(roundedRect: filled, xRadius: 3, yRadius: 3).fill()
    }

    /// Draws a white thumb with the same blue outline as the filled track.
    override func drawKnob(
        _ knobRect: NSRect
    ) {
        let diameter: CGFloat = 18
        let rect = NSRect(
            x: knobRect.midX - diameter / 2,
            y: knobRect.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
        let path = NSBezierPath(ovalIn: rect)
        NSColor.white.setFill()
        path.fill()
        Palette.accent.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}
