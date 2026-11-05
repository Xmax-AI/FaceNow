//
//  GenerationWorkspaceView.swift
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
import UniformTypeIdentifiers
import XmaxSDK
import Combine

/// Owns generation previews, reference modes, prompt editing, and image import.
@MainActor
final class GenerationWorkspaceView: Canvas {

    /// The generation state rendered by the persistent controls.
    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    /// The view-specific formatting of the repository's current metrics.
    private lazy var statistics: GenerationStatisticsViewModel = {
        let viewModel = GenerationStatisticsViewModel()
        return viewModel
    }()

    // MARK: - Views

    /// The local preview kept mounted while capture readiness is established.
    private lazy var localPanel: GenerationVideoPanel = {
        let view = GenerationVideoPanel(
            title: GenerationStrings.controlsLocal,
            statistics: statistics.localStatisticsPanels
        )
        return view
    }()

    /// The generated-result preview and its independent downlink statistics.
    private lazy var resultPanel: GenerationVideoPanel = {
        let view = GenerationVideoPanel(
            title: GenerationStrings.controlsResult,
            statistics: statistics.remoteStatisticsPanels,
            showsWatermark: true
        )
        return view
    }()

    /// The audio control row shared by both video panels, outside their output pixels.
    private lazy var audioControls: GenerationAudioControlsView = {
        let view = GenerationAudioControlsView()
        return view
    }()

    /// Uses the same painted Canvas surface as statistics for the lower-right result controls.
    private lazy var beautyOverlay: GenerationBeautyPanelView = {
        let view = GenerationBeautyPanelView()
        view.isHidden = true
        view.alphaValue = 0
        return view
    }()

    /// Tracks the rendered overlay while repository state owns the effect preference.
    private var beautyVisible = false

    /// Cancels an interrupted dismissal before a new reveal can be hidden by stale work.
    private var beautyDismissal: Task<Void, Never>?

    /// The shared tab group containing the persistent generation-mode controls.
    private lazy var tabs: TabSwitcher = {
        let view = TabSwitcher(
            titles: GenerationMode.allCases.map(\.title),
            distribution: .content
        )
        view.font = .systemFont(ofSize: 13.5, weight: .medium)
        view.onSelectionChanged = { [weak self] index in
            guard let self, !self.generationRepo.isBusy else { return }
            self.generationRepo.activeMode = GenerationMode.allCases[index]
        }
        return view
    }()

    /// The persistent reference grid for each mode with preset images.
    private var lists: [GenerationMode: GenerationReferenceListView] = [:]

    /// The bordered Free Prompt editor and optional reference controls.
    private lazy var promptContainer: Canvas = {
        let view = Canvas(
            color: Palette.surface,
            radius: 18
        )
        view.layer?.borderWidth = 1
        view.layer?.borderColor = Palette.border.cgColor
        return view
    }()

    /// The native scroll container tracking the prompt editor's width.
    private lazy var promptScroll: NSScrollView = {
        let view = NSScrollView()
        view.drawsBackground = false
        view.hasVerticalScroller = true
        return view
    }()

    /// The composition-aware native prompt editor.
    private lazy var promptEditor: GenerationPromptTextView = {
        let view = GenerationPromptTextView()
        view.placeholder = GenerationStrings.controlsDescribeHowYouWantTheVideoToChange
        view.placeholderColor = Palette.secondary
        view.onCommittedTextChange = { [weak self] text in
            guard let self, self.generationRepo.prompt != text else { return }
            self.generationRepo.prompt = text
        }
        view.font = .systemFont(ofSize: 15)
        view.textColor = Palette.text
        view.isRichText = false
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.setAccessibilityLabel(GenerationStrings.controlsDescribeHowYouWantTheVideoToChange)
        return view
    }()

    /// The compact upload or reference control used by Free Prompt.
    private lazy var freeReference: GenerationReferenceButton = {
        let view = GenerationReferenceButton()
        view.compact = true
        view.onClick = { [weak self] in
            guard let self else { return }
            if let reference = self.generationRepo.freeReference, reference.uploadState == .error {
                Task { [weak self] in await self?.generationRepo.selectReference(reference) }
            } else if self.generationRepo.freeReference == nil {
                self.presentImporter(mode: .free)
            }
        }
        return view
    }()

    /// Removes the Free Prompt reference while retaining a larger hit area.
    private lazy var removeReference: Button = {
        let view = Button(
            icon: .close,
            style: .dismiss
        )
        view.toolTip = GenerationStrings.controlsRemoveReference
        view.setAccessibilityLabel(GenerationStrings.controlsRemoveReference)
        view.iconSize = 11
        view.foregroundColor = .white
        view.backgroundInset = 6
        view.leadingPadding = 0
        view.trailingPadding = 0
        view.onClick = { [weak self] in self?.generationRepo.removeFreeReference() }
        return view
    }()

    /// Submits the current Free Prompt contents to generation.
    private lazy var submitButton: Button = {
        let view = Button(
            icon: .arrow,
            style: .primary
        )
        view.iconSize = 20
        view.showsShadow = false
        view.setAccessibilityLabel(GenerationStrings.controlsSubmitPrompt)
        view.onClick = { [weak self] in Task { [weak self] in await self?.generationRepo.submitPrompt() } }
        return view
    }()

    /// The previously visible mode, used to end editing when leaving Free Prompt.
    private var displayedMode: GenerationMode?

    /// Creates the workspace and binds its user actions once.
    init() {
        super.init()
        configureWorkspace()
    }

    /// Storyboard decoding is unsupported for this programmatic view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Measures both video panels and the reference editor at the current width.
    func preferredHeight(
        contentWidth: CGFloat
    ) -> CGFloat {
        let panelWidth = (contentWidth - 24) / 2
        return panelWidth * CGFloat(VirtualCameraConfiguration.height) / CGFloat(VirtualCameraConfiguration.width)
            + 12 + GenerationAudioControlsView.preferredHeight + 24 + 42 + 28
            + 190
    }

    /// Updates existing controls while retaining preview bindings during startup.
    func update() {
        audioControls.update()
        let active = generationRepo.sessionActive
        if active && !generationRepo.isClosing {
            setBeautyVisible(generationRepo.beautyEnabled)
        } else {
            setBeautyVisible(false, animated: false)
        }
        // The preview is bound even while the landing page is visible, as required by SDK readiness.
        localPanel.update(
            track: generationRepo.localStream?.videoTrack,
            message: "",
            statistics: statistics.localStatisticsPanels,
            visible: generationRepo.statisticsVisible
        )
        let placeholder =
            generationRepo.state.connectionState == .generating && generationRepo.remoteStream != nil
            ? ""
            : [.connected, .generating].contains(generationRepo.state.connectionState)
                ? GenerationStrings.controlsGenerating : GenerationStrings.controlsWaitingForConnection
        resultPanel.update(
            track: generationRepo.remoteStream?.videoTrack,
            message: placeholder,
            statistics: statistics.remoteStatisticsPanels,
            visible: generationRepo.statisticsVisible
        )
        tabs.selectedIndex = GenerationMode.allCases.firstIndex(of: generationRepo.activeMode)
        tabs.isEnabled = !generationRepo.isBusy
        for (mode, list) in lists {
            let visible = active && generationRepo.activeMode == mode
            if !visible && !list.isHidden { list.suspendImages() }
            list.isHidden = !visible
            if visible {
                list.update(
                    references: generationRepo.uploadedReferences.filter { $0.mode == mode } + mode.presets,
                    selectedID: generationRepo.selectedReferenceID,
                    enabled: generationRepo.canGenerate,
                    dimmed: !generationRepo.canGenerate && !generationRepo.interpolationSwitching
                )
            }
        }
        promptContainer.isHidden = generationRepo.activeMode != .free
        promptEditor.isEditable = !generationRepo.isClosing
        if !promptEditor.hasMarkedText(), promptEditor.string != generationRepo.prompt {
            promptEditor.string = generationRepo.prompt
        }
        if active && generationRepo.activeMode == .free {
            freeReference.configure(
                generationRepo.freeReference,
                selected: false,
                enabled: generationRepo.canGenerate
            )
        } else {
            freeReference.thumbnail.cancel()
        }
        removeReference.isHidden = generationRepo.freeReference == nil
        removeReference.isEnabled = !generationRepo.isBusy
        submitButton.isEnabled = generationRepo.canGenerate && !generationRepo.referenceUploading
        if displayedMode != generationRepo.activeMode {
            // Resign the editor when switching modes so hidden text cannot receive keyboard input.
            if displayedMode == .free { window?.makeFirstResponder(nil) }
            displayedMode = generationRepo.activeMode
        }
    }

    /// Cancels image work when the application is shutting down.
    func suspendImages() {
        setBeautyVisible(false, animated: false)
        for list in lists.values { list.suspendImages() }
        freeReference.thumbnail.cancel()
    }

    /// Toggles the effect and its controls together using the saved business state.
    func toggleBeauty() {
        guard generationRepo.sessionActive, !generationRepo.isClosing, window != nil else { return }
        generationRepo.setBeautyEnabled(!generationRepo.beautyEnabled)
        setBeautyVisible(generationRepo.beautyEnabled)
    }

    /// Fades the overlay using shared control timing and cancels stale delayed dismissals.
    private func setBeautyVisible(
        _ visible: Bool,
        animated: Bool = true
    ) {
        if !animated {
            beautyDismissal?.cancel()
            beautyDismissal = nil
            beautyVisible = visible
            beautyOverlay.isHidden = !visible
            ControlMotion.setOpacity(visible ? 1 : 0, on: beautyOverlay, duration: 0)
            return
        }
        guard beautyVisible != visible else { return }
        beautyVisible = visible
        beautyDismissal?.cancel()
        beautyDismissal = nil
        if visible {
            let wasHidden = beautyOverlay.isHidden
            beautyOverlay.isHidden = false
            ControlMotion.setOpacity(1, on: beautyOverlay, from: wasHidden ? 0 : nil)
        } else {
            ControlMotion.setOpacity(0, on: beautyOverlay)
            guard ControlMotion.isAnimated(in: beautyOverlay) else {
                beautyOverlay.isHidden = true
                return
            }
            beautyDismissal = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(ControlMotion.duration)) } catch { return }
                guard let self, !self.beautyVisible else { return }
                self.beautyOverlay.isHidden = true
                self.beautyDismissal = nil
            }
        }
    }

    /// Releases overlay editing when the workspace returns to home or login.
    override func viewDidHide() {
        super.viewDidHide()
        audioControls.closePopovers()
        setBeautyVisible(false, animated: false)
    }

    /// Cancels view-owned animation work when its window detaches.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            audioControls.closePopovers()
            setBeautyVisible(false, animated: false)
        }
    }

    /// Keeps panels, tabs, references, and prompt controls in one persistent constraint graph.
    private func configureLayout() {
        localPanel.snp.makeConstraints { make in
            make.leading.top.equalToSuperview()
            make.trailing.equalTo(resultPanel.snp.leading).offset(-24)
            make.width.equalTo(resultPanel)
            make.height.equalTo(localPanel.snp.width).multipliedBy(
                CGFloat(VirtualCameraConfiguration.height) / CGFloat(VirtualCameraConfiguration.width)
            )
        }
        resultPanel.snp.makeConstraints { make in
            make.trailing.top.equalToSuperview()
            make.height.equalTo(localPanel)
        }
        audioControls.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(localPanel.snp.bottom).offset(12)
            make.height.equalTo(GenerationAudioControlsView.preferredHeight)
        }
        beautyOverlay.snp.makeConstraints { make in
            make.trailing.bottom.equalTo(resultPanel).inset(12)
            make.width.equalTo(beautyOverlay.preferredWidth).priority(490)
            make.width.lessThanOrEqualTo(resultPanel.snp.width).offset(-24)
            make.height.lessThanOrEqualTo(resultPanel.snp.height).offset(-24).priority(490)
        }
        tabs.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(audioControls.snp.bottom).offset(24)
            make.width.lessThanOrEqualToSuperview()
            make.width.equalTo(tabs.preferredWidth).priority(490)
            make.height.equalTo(42)
        }
        for list in lists.values {
            list.snp.makeConstraints { make in
                make.leading.trailing.equalToSuperview()
                make.top.equalTo(tabs.snp.bottom).offset(28)
                make.height.equalTo(190)
            }
        }
        promptContainer.snp.makeConstraints { make in
            // A preferred fill width must yield before AppKit's window-size priority, including while hidden.
            make.centerX.equalToSuperview()
            make.top.equalTo(tabs.snp.bottom).offset(32)
            make.width.equalToSuperview().priority(490)
            make.width.lessThanOrEqualTo(880)
            make.height.equalTo(160)
        }
        promptScroll.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview().inset(18)
            make.height.equalTo(78)
        }
        promptEditor.snp.makeConstraints { make in
            make.leading.top.equalTo(promptScroll.contentView)
            make.width.equalTo(promptScroll.contentView)
            make.height.greaterThanOrEqualTo(promptScroll.contentView)
        }
        submitButton.snp.makeConstraints { make in
            make.trailing.bottom.equalToSuperview().inset(12)
            make.size.equalTo(44)
        }
        freeReference.snp.makeConstraints { make in
            make.trailing.equalTo(submitButton.snp.leading).offset(-10)
            make.centerY.equalTo(submitButton)
            make.size.equalTo(44)
        }
        removeReference.snp.makeConstraints { make in
            make.leading.equalTo(freeReference.snp.leading).offset(22)
            make.top.equalTo(freeReference.snp.top).offset(-12)
            make.size.equalTo(32)
        }
    }

    /// Builds persistent generation controls and binds their mode-specific actions.
    private func configureWorkspace() {
        [localPanel, resultPanel, audioControls, tabs, promptContainer].forEach(addSubview)
        resultPanel.addSubview(beautyOverlay)
        for mode in GenerationMode.allCases {
            if mode != .free {
                let list = GenerationReferenceListView()
                list.onUpload = { [weak self] in self?.presentImporter(mode: mode) }
                list.onSelect = { [weak self] reference in
                    Task { [weak self] in await self?.generationRepo.selectReference(reference) }
                }
                addSubview(list)
                lists[mode] = list
            }
        }
        promptScroll.documentView = promptEditor
        [promptScroll, freeReference, removeReference, submitButton].forEach(promptContainer.addSubview)
        // Keep a 32pt hit area around the smaller 20pt circular background.
        removeReference.isBordered = true
        configureLayout()
    }

    /// Opens a single-image picker and forwards the selected security-scoped file for upload.
    private func presentImporter(
        mode: GenerationMode
    ) {
        guard generationRepo.canGenerate, let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                await self?.generationRepo.uploadReference(
                    at: url,
                    mode: mode
                )
            }
        }
    }

}

/// Presents only the four result strengths over the shared translucent video surface.
@MainActor
private final class GenerationBeautyPanelView: Canvas {

    /// Owns saved strengths and applies user edits to the common result output.
    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    /// Refreshes values after repository publications have completed.
    private var observation: AnyCancellable?

    /// Shares localized labels and writable strength bindings between sizing and control creation.
    private static let settings: [(String, WritableKeyPath<RealtimeVideoBeautyOptions, Float>)] = [
        (GenerationStrings.beautySmoothness, \.smoothness),
        (GenerationStrings.beautyLightening, \.lightening),
        (GenerationStrings.beautySharpness, \.sharpness),
        (GenerationStrings.beautyRedness, \.redness),
    ]

    /// Fits localized labels, a 90-point slider track, percentages, gaps, and surface padding.
    let preferredWidth: CGFloat

    /// Reserves one shared label width so the four slider tracks align.
    private let labelWidth: CGFloat

    /// Aligns all slider tracks after the widest localized strength label.
    private lazy var rows: [(WritableKeyPath<RealtimeVideoBeautyOptions, Float>, GenerationBeautySliderRow)] = {
        return Self.settings.map { title, key in
            let row = GenerationBeautySliderRow(title: title, labelWidth: labelWidth)
            row.onChange = { [weak self] value in
                guard let self, self.generationRepo.beautyEnabled, !self.generationRepo.isClosing else { return }
                var options = self.generationRepo.beautyOptions
                options[keyPath: key] = value
                self.generationRepo.setBeautyOptions(options)
            }
            return (key, row)
        }
    }()

    /// Paints the same rounded translucent black surface as the statistics overlays.
    init() {
        let font = NSFont.systemFont(ofSize: 11)
        labelWidth = ceil(Self.settings.map { Typography.size($0.0, font: font).width }.max() ?? 0)
        preferredWidth = labelWidth + 148
        super.init(color: .black.withAlphaComponent(0.6), radius: 8)
        appearance = NSAppearance(named: .darkAqua)
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        rows.forEach { addSubview($0.1) }
        var previous: NSView?
        for (_, row) in rows {
            row.snp.makeConstraints { make in
                make.leading.trailing.equalToSuperview().inset(8)
                make.height.equalTo(22)
                if let previous {
                    make.top.equalTo(previous.snp.bottom).offset(2)
                } else {
                    make.top.equalToSuperview().inset(8)
                }
            }
            previous = row
        }
        previous?.snp.makeConstraints { make in make.bottom.equalToSuperview().inset(8) }
        observation = generationRepo.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.update() }
        }
        update()
    }

    /// Storyboard decoding is unsupported for this programmatic panel.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Reflects strengths without allowing a fading control to reactivate a disabled effect.
    private func update() {
        rows.forEach { key, row in
            row.update(
                value: generationRepo.beautyOptions[keyPath: key],
                enabled: generationRepo.beautyEnabled && !generationRepo.isClosing
            )
        }
    }
}

/// Presents one native continuous slider with a proportional-font percentage label.
@MainActor
private final class GenerationBeautySliderRow: Canvas {

    /// Delivers normalized user input while programmatic updates remain silent.
    var onChange: ((Float) -> Void)?

    /// Names the selected strength for both sighted users and accessibility clients.
    private lazy var titleLabel: NSTextField = {
        let view = NSTextField(labelWithString: "")
        view.font = .systemFont(ofSize: 11)
        view.textColor = .white.withAlphaComponent(0.9)
        return view
    }()

    /// Displays the full normalized range in familiar percentage units.
    private lazy var valueLabel: NSTextField = {
        let view = NSTextField(labelWithString: "")
        view.font = .systemFont(ofSize: 11)
        view.textColor = .white.withAlphaComponent(0.9)
        view.alignment = .right
        return view
    }()

    /// Uses native keyboard, pointer, and accessibility behavior for continuous editing.
    private lazy var slider: NSSlider = {
        let view = NSSlider()
        view.minValue = 0
        view.maxValue = 100
        view.isContinuous = true
        view.controlSize = .mini
        view.target = self
        view.action = #selector(sliderChanged)
        return view
    }()

    /// Aligns the strength label, slider, and percentage in a single compact row.
    init(
        title: String,
        labelWidth: CGFloat
    ) {
        super.init()
        titleLabel.stringValue = title
        slider.setAccessibilityLabel(title)
        [titleLabel, valueLabel, slider].forEach(addSubview)
        titleLabel.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
            make.width.equalTo(labelWidth)
        }
        valueLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.lastBaseline.equalTo(titleLabel.snp.lastBaseline)
            make.width.equalTo(30)
        }
        slider.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel.snp.trailing).offset(6)
            make.trailing.equalTo(valueLabel.snp.leading).offset(-6)
            make.centerY.equalToSuperview()
        }
    }

    /// Storyboard decoding is unsupported for this programmatic row.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Reflects repository strengths without disturbing native slider tracking.
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

    /// Publishes only user-driven value changes.
    @objc private func sliderChanged() {
        let percent = Int(slider.doubleValue.rounded())
        valueLabel.stringValue = GenerationStrings.percentage(value: percent)
        onChange?(Float(percent) / 100)
    }
}
