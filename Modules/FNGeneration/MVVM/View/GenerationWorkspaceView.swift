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
            + 34 + 42 + 28
            + 190
    }

    /// Updates existing controls while retaining preview bindings during startup.
    func update() {
        let active = generationRepo.sessionActive
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
        for list in lists.values { list.suspendImages() }
        freeReference.thumbnail.cancel()
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
        tabs.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(localPanel.snp.bottom).offset(34)
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
        [localPanel, resultPanel, tabs, promptContainer].forEach(addSubview)
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
