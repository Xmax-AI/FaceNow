//
//  GenerationTranslationDialogView.swift
//  FaceNow
//

import AppKit
import SnapKit

/// Presents live translation configuration in the center of the generation window.
@MainActor
final class GenerationTranslationDialogView: Canvas {

    /// Aligns the status, field labels, and language pack heading.
    private static let labelFont = NSFont.systemFont(ofSize: 14, weight: .semibold)

    /// Returns to the generation workspace while preserving the selected settings.
    var onClose: (() -> Void)?

    /// Opens the shared microphone permission guide.
    var onShowMicrophoneSetup: (() -> Void)?

    /// Supplies localized choices and the current capture state.
    private let model: GenerationTranslationViewModel

    /// Owns the resource query for the current pair while this dialog is visible.
    private var resourceTask: Task<Void, Never>?

    /// Retains the overlay until its closing animation finishes.
    private var dismissalTask: Task<Void, Never>?

    /// Blocks interaction while the card and backdrop animate out.
    private var isDismissing = false

    private var expandedCardBottom: Constraint?
    private var compactCardBottom: Constraint?

    /// Groups the controls shown below the microphone picker.
    private let translationOptions = NSView()

    /// Dims the covered workspace and dismisses the dialog on outside clicks.
    private lazy var backdrop: Canvas = {
        let view = Canvas(color: .black.withAlphaComponent(0.35))
        view.setAccessibilityElement(false)
        view.addGestureRecognizer(NSClickGestureRecognizer(
            target: self,
            action: #selector(closeFromBackdrop)
        ))
        return view
    }()

    /// Contains the configuration and traps accessibility navigation within it.
    private lazy var card: Canvas = {
        let view = Canvas(color: .white, radius: 16)
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowOpacity = 0.16
        view.layer?.shadowRadius = 24
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel(GenerationStrings.translation)
        view.setAccessibilityModal(true)
        return view
    }()

    /// Names the dialog in the generation page's system typography.
    private lazy var title: NSTextField = {
        let view = NSTextField(labelWithString: GenerationStrings.translation)
        view.font = .systemFont(ofSize: 22, weight: .semibold)
        view.textColor = Palette.text
        return view
    }()

    /// Separates capture status from the configurable fields.
    private lazy var statusCard: Canvas = {
        let view = Canvas(color: Palette.surface, radius: 10)
        return view
    }()

    /// Labels the current capture state.
    private lazy var statusTitle: NSTextField = {
        let view = NSTextField(labelWithString: GenerationStrings.translationStatus)
        view.font = Self.labelFont
        view.textColor = Palette.text
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        return view
    }()

    /// Shows capture progress and prerequisites on one line.
    private lazy var statusValue: NSTextField = {
        let view = NSTextField(labelWithString: "")
        view.font = .systemFont(ofSize: 13)
        view.textColor = Palette.secondary
        view.lineBreakMode = .byTruncatingTail
        view.alignment = .right
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }()

    /// Reinforces the written status with a colored dot.
    private lazy var statusDot: Canvas = {
        let view = Canvas(color: Palette.secondary, radius: 4)
        view.setAccessibilityElement(false)
        return view
    }()

    /// Uses the same microphone selection and permission workflow as the generation toolbar.
    private lazy var microphone: HomeInputPickerView = {
        let view = HomeInputPickerView(input: .microphone, presentation: .toolbar)
        view.onShowMicrophoneSetup = { [weak self] in self?.onShowMicrophoneSetup?() }
        return view
    }()

    /// Selects the language sent to the speech recognizer.
    private lazy var source: NSPopUpButton = {
        let view = NSPopUpButton(frame: .zero, pullsDown: false)
        view.target = self
        view.action = #selector(selectLanguage(_:))
        view.setAccessibilityLabel(GenerationStrings.translationSourceLanguage)
        return view
    }()

    /// Selects the language displayed in the translated captions.
    private lazy var target: NSPopUpButton = {
        let view = NSPopUpButton(frame: .zero, pullsDown: false)
        view.target = self
        view.action = #selector(selectLanguage(_:))
        view.setAccessibilityLabel(GenerationStrings.translationTargetLanguage)
        return view
    }()

    /// Labels the management list for the currently selected language pair.
    private lazy var resourceTitle: NSTextField = {
        let view = NSTextField(labelWithString: GenerationStrings.translationLanguagePacks)
        view.font = Self.labelFont
        view.textColor = Palette.text
        return view
    }()

    /// Displays the selected speech model and its actual installation progress.
    private lazy var sourceResource: TranslationResourceRowView = {
        let view = TranslationResourceRowView { [weak self] in
            guard let self, let window = self.window else { return }
            self.model.repository.downloadTranslationResource(.recognition, in: window)
        }
        return view
    }()

    /// Lists the translation languages and requests the system download in this window.
    private lazy var targetResource: TranslationResourceRowView = {
        let view = TranslationResourceRowView { [weak self] in
            guard let self, let window = self.window else { return }
            self.model.repository.downloadTranslationResource(.translation, in: window)
        }
        return view
    }()

    /// Closes configuration without stopping an active translation.
    private lazy var closeButton: Button = {
        let view = Button(style: .plain)
        view.symbolName = "xmark"
        view.centersSymbolVisually = true
        view.iconSize = 16
        view.foregroundColor = Palette.secondary
        view.hoverBackgroundColor = Palette.surface
        view.cornerRadius = 8
        view.showsShadow = false
        view.toolTip = GenerationStrings.translationCloseDialog
        view.setAccessibilityLabel(GenerationStrings.translationCloseDialog)
        view.keyEquivalent = "\u{1b}"
        view.keyEquivalentModifierMask = []
        view.onClick = { [weak self] in
            guard let self, !self.isDismissing else { return }
            self.onClose?()
        }
        return view
    }()

    /// Starts or stops translation explicitly while the dialog shows status updates.
    private lazy var runButton: Button = {
        let view = Button(GenerationStrings.translationStart, style: .primary)
        view.font = .systemFont(ofSize: 14, weight: .medium)
        view.cornerRadius = 9
        view.showsShadow = false
        view.onClick = { [weak self] in
            guard let self, self.model.canToggle else { return }
            if self.model.repository.toggleTranslation() {
                self.onClose?()
            } else {
                self.update()
            }
        }
        return view
    }()

    /// Builds one configuration card backed by the current session.
    init(
        repository: GenerationRepository
    ) {
        model = GenerationTranslationViewModel(repository: repository)
        super.init()
        [backdrop, card].forEach(addSubview)
        [title, statusCard, closeButton, translationOptions].forEach(card.addSubview)
        [statusTitle, statusDot, statusValue].forEach(statusCard.addSubview)
        [resourceTitle, sourceResource, targetResource, runButton].forEach(translationOptions.addSubview)
        configureLayout()
        backdrop.layer?.opacity = 0
        card.layer?.opacity = 0
        updateKeyLoop()
        setAccessibilityChildren([card])
    }

    /// Storyboard decoding is unsupported for this programmatic dialog.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Keeps keyboard input inside the modal during its exit.
    override var acceptsFirstResponder: Bool { true }

    /// Shows the dialog and checks resources without starting the microphone.
    func present() {
        model.repository.refreshMicrophones()
        refreshResources()
        animatePresentation(visible: true)
        window?.makeFirstResponder(closeButton)
    }

    /// Completes user dismissal after the shared modal exit, or detaches immediately for lifecycle changes.
    func dismiss(
        animated: Bool,
        completion: @escaping @MainActor () -> Void
    ) {
        guard !isDismissing || !animated else { return }
        dismissalTask?.cancel()
        dismissalTask = nil
        isDismissing = true
        microphone.closePicker()
        window?.makeFirstResponder(self)
        guard animated, ControlMotion.isAnimated(in: self) else {
            completion()
            return
        }
        animatePresentation(visible: false)
        dismissalTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(ControlMotion.duration)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.dismissalTask = nil
            completion()
        }
    }

    /// Releases dialog-owned work before the overlay is detached.
    func shutdown() {
        dismissalTask?.cancel()
        dismissalTask = nil
        resourceTask?.cancel()
        microphone.closePicker()
    }

    /// Reflects device, resource, and capture changes without replacing live controls.
    func update() {
        guard !isDismissing else { return }
        let repo = model.repository
        microphone.update()
        updateStatus(model.status)
        let showsOptions = model.showsTranslationOptions
        setTranslationOptionsVisible(showsOptions)
        guard showsOptions else { return }
        populate(source, choices: model.sourceChoices, selected: repo.translationLanguages.source)
        populate(target, choices: model.targetChoices, selected: repo.translationLanguages.target)
        let canChangeLanguages = model.canChangeLanguages
        if source.isEnabled != canChangeLanguages { source.isEnabled = canChangeLanguages }
        if target.isEnabled != canChangeLanguages { target.isEnabled = canChangeLanguages }
        sourceResource.update(model.resourceRow(for: .recognition))
        targetResource.update(model.resourceRow(for: .translation))
        let runTitle = repo.translationState == .off ? GenerationStrings.translationStart : GenerationStrings.translationStop
        if runButton.title != runTitle { runButton.title = runTitle }
        if runButton.isEnabled != model.canToggle { runButton.isEnabled = model.canToggle }
    }

    /// Sizes the card and keeps keyboard focus on visible controls.
    private func setTranslationOptionsVisible(
        _ visible: Bool
    ) {
        let hidden = !visible
        guard translationOptions.isHidden != hidden else { return }
        if !visible, let focused = window?.firstResponder as? NSView, focused.isDescendant(of: translationOptions) {
            if window?.makeFirstResponder(microphone.focusControl) != true {
                window?.makeFirstResponder(closeButton)
            }
        }
        translationOptions.isHidden = hidden
        if visible {
            compactCardBottom?.deactivate()
            expandedCardBottom?.activate()
        } else {
            expandedCardBottom?.deactivate()
            compactCardBottom?.activate()
        }
        updateKeyLoop()
    }

    /// Cycles through the visible configuration controls.
    private func updateKeyLoop() {
        var focusOrder = [closeButton, microphone.focusControl]
        if !translationOptions.isHidden {
            focusOrder += [source, target, sourceResource.focusControl, targetResource.focusControl, runButton]
        }
        for (index, control) in focusOrder.enumerated() {
            control.nextKeyView = focusOrder[(index + 1) % focusOrder.count]
        }
    }

    /// Keeps full recovery guidance available alongside the compact status.
    private func updateStatus(
        _ status: GenerationTranslationViewModel.Status
    ) {
        let color: NSColor = switch status.tone {
        case .idle, .blocked: Palette.destructive
        case .pending: .systemOrange
        case .ready: Palette.success
        }
        if statusValue.stringValue.isEmpty {
            statusDot.layer?.backgroundColor = color.cgColor
        } else {
            ControlMotion.set(color.cgColor, for: "backgroundColor", on: statusDot.layer, in: statusDot)
        }
        if statusValue.stringValue != status.title { statusValue.stringValue = status.title }
        if statusValue.toolTip != status.detail {
            statusValue.toolTip = status.detail
            statusValue.setAccessibilityHelp(status.detail == status.title ? nil : status.detail)
        }
    }

    /// Keeps clicks and scroll events from reaching the covered workspace.
    override func hitTest(
        _ point: NSPoint
    ) -> NSView? {
        guard !isHidden, bounds.contains(convert(point, from: superview)) else { return nil }
        return isDismissing ? self : super.hitTest(point) ?? self
    }

    override func mouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    /// Closes the dialog without passing the click to the workspace underneath.
    @objc private func closeFromBackdrop() {
        if !isDismissing { onClose?() }
    }

    /// Treats Escape as closing configuration without changing capture state.
    override func cancelOperation(
        _ sender: Any?
    ) {
        if !isDismissing { onClose?() }
    }

    /// Uses the same backdrop fade and 24-point travel as the About Us modal.
    private func animatePresentation(
        visible: Bool
    ) {
        ControlMotion.setModalVisible(
            visible,
            backdrop: backdrop,
            card: card,
            in: self
        ) {
            card.snp.updateConstraints { make in make.centerY.equalToSuperview().offset(visible ? 0 : 24) }
        }
    }

    /// Polls availability while visible and lets repository changes drive the display.
    private func refreshResources() {
        resourceTask?.cancel()
        update()
        resourceTask = Task { [weak self, model] in
            if await model.loadLanguagesIfNeeded() { self?.update() }
            while !Task.isCancelled, self?.isDismissing == false {
                await model.repository.refreshTranslationResources()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    /// Applies the selected language while leaving the other side of the pair intact.
    @objc private func selectLanguage(
        _ sender: NSPopUpButton
    ) {
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        let pair = model.repository.translationLanguages
        let selection = MicrophoneTranslation.LanguagePair(
            source: sender === source ? id : pair.source,
            target: sender === target ? id : pair.target
        )
        guard selection != pair else { return }
        model.repository.selectTranslationLanguages(selection)
        refreshResources()
    }

    /// Rebuilds a menu only when system choices change, keeping selection by stable identifier.
    private func populate(
        _ picker: NSPopUpButton,
        choices: [GenerationTranslationViewModel.Choice],
        selected: String
    ) {
        if picker.itemArray.compactMap({ $0.representedObject as? String }) != choices.map(\.id) {
            picker.removeAllItems()
            let byTitle = Dictionary(grouping: choices, by: \.title)
            for choice in choices {
                let title = byTitle[choice.title]?.count == 1 ? choice.title : "\(choice.title) (\(choice.id))"
                picker.addItem(withTitle: title)
                picker.lastItem?.representedObject = choice.id
            }
        }
        if let index = choices.firstIndex(where: { $0.id == selected }), picker.indexOfSelectedItem != index {
            picker.selectItem(at: index)
        }
    }

    /// Centers the card and aligns form labels and controls with common spacing.
    private func configureLayout() {
        backdrop.snp.makeConstraints { make in make.edges.equalToSuperview() }
        card.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(24)
            make.width.equalTo(460).priority(490)
            make.width.lessThanOrEqualToSuperview().offset(-48)
        }
        title.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(24)
            make.trailing.lessThanOrEqualTo(closeButton.snp.leading).offset(-8)
        }
        closeButton.snp.makeConstraints { make in
            make.centerY.equalTo(title)
            make.trailing.equalToSuperview().inset(20)
            make.size.equalTo(32)
        }
        statusCard.snp.makeConstraints { make in
            make.top.equalTo(title.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(44)
        }
        statusTitle.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(12)
            make.centerY.equalToSuperview()
        }
        statusValue.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(12)
            make.centerY.equalToSuperview()
        }
        statusDot.snp.makeConstraints { make in
            make.leading.greaterThanOrEqualTo(statusTitle.snp.trailing).offset(12)
            make.trailing.equalTo(statusValue.snp.leading).offset(-6)
            make.centerY.equalToSuperview()
            make.size.equalTo(8)
        }

        let microphoneRow = makeField(GenerationStrings.translationInput, control: microphone)
        let sourceRow = makeField(GenerationStrings.translationSourceLanguage, control: source)
        let targetRow = makeField(GenerationStrings.translationTargetLanguage, control: target)
        card.addSubview(microphoneRow)
        [sourceRow, targetRow].forEach(translationOptions.addSubview)
        microphoneRow.snp.makeConstraints { make in
            make.top.equalTo(statusCard.snp.bottom).offset(16)
            make.leading.trailing.equalTo(statusCard)
        }
        compactCardBottom = microphoneRow.snp.prepareConstraints { make in
            make.bottom.equalTo(card).inset(24)
        }.first
        translationOptions.snp.makeConstraints { make in
            make.top.equalTo(microphoneRow.snp.bottom).offset(4)
            make.leading.trailing.equalTo(microphoneRow)
            expandedCardBottom = make.bottom.equalTo(card).inset(24).constraint
        }
        sourceRow.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        targetRow.snp.makeConstraints { make in
            make.top.equalTo(sourceRow.snp.bottom).offset(4)
            make.leading.trailing.equalToSuperview()
        }
        resourceTitle.snp.makeConstraints { make in
            make.top.equalTo(targetRow.snp.bottom).offset(16)
            make.leading.equalToSuperview()
        }
        sourceResource.snp.makeConstraints { make in
            make.top.equalTo(resourceTitle.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview()
        }
        targetResource.snp.makeConstraints { make in
            make.top.equalTo(sourceResource.snp.bottom).offset(6)
            make.leading.trailing.equalTo(sourceResource)
        }
        runButton.snp.makeConstraints { make in
            make.top.equalTo(targetResource.snp.bottom).offset(16)
            make.trailing.bottom.equalToSuperview()
            make.width.equalTo(154)
            make.height.equalTo(40)
        }
    }

    /// Aligns each selector with its label in the shared form grid.
    private func makeField(
        _ title: String,
        control: NSView
    ) -> NSView {
        let row = NSView()
        let label = NSTextField(labelWithString: title)
        label.font = Self.labelFont
        label.textColor = Palette.text
        [label, control].forEach(row.addSubview)
        row.snp.makeConstraints { make in make.height.equalTo(36) }
        label.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
            make.width.equalTo(126)
        }
        control.snp.makeConstraints { make in
            make.leading.equalTo(label.snp.trailing).offset(12)
            make.trailing.centerY.equalToSuperview()
        }
        return row
    }
}

/// Shows one language resource with a progress bar only while it is downloading.
@MainActor
private final class TranslationResourceRowView: Canvas {

    /// Opens the resource's download action.
    private let onAction: () -> Void

    /// Names the language selected for this row.
    private lazy var language: NSTextField = {
        let view = NSTextField(labelWithString: "")
        view.font = .systemFont(ofSize: 13, weight: .medium)
        view.textColor = Palette.text
        view.lineBreakMode = .byTruncatingTail
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }()

    /// Shows the localized installation state and any reported percentage.
    private lazy var status: NSTextField = {
        let view = NSTextField(labelWithString: "")
        view.font = .systemFont(ofSize: 12)
        view.textColor = Palette.secondary
        view.alignment = .right
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        return view
    }()

    /// Uses determinate progress only when it comes from the framework.
    private lazy var progress: NSProgressIndicator = {
        let view = NSProgressIndicator()
        view.style = .bar
        view.controlSize = .small
        view.minValue = 0
        view.maxValue = 100
        view.isHidden = true
        view.setAccessibilityElement(false)
        return view
    }()

    /// Shows the action next to the affected resource.
    private lazy var actionButton: Button = {
        let view = Button(GenerationStrings.translationDownloadResource, style: .plain)
        view.font = .systemFont(ofSize: 12, weight: .medium)
        view.foregroundColor = Palette.accent
        view.restingBackgroundColor = .white
        view.hoverBackgroundColor = Palette.accent.withAlphaComponent(0.10)
        view.leadingPadding = 8
        view.trailingPadding = 8
        view.cornerRadius = 6
        view.showsShadow = false
        view.isHidden = true
        view.onClick = { [weak self] in self?.onAction() }
        return view
    }()

    /// Includes the row's action in the dialog's keyboard navigation.
    var focusControl: NSView { actionButton }

    /// Keeps failure text and retry side by side so the card height stays constant.
    private lazy var statusControls: NSStackView = {
        let view = NSStackView(views: [status, actionButton])
        view.orientation = .horizontal
        view.alignment = .centerY
        view.spacing = 6
        view.detachesHiddenViews = true
        return view
    }()

    /// Centers visible controls and places download progress below their text.
    private lazy var rowControls: NSStackView = {
        let view = NSStackView(views: [statusControls, progress])
        view.orientation = .vertical
        view.alignment = .trailing
        view.spacing = 3
        view.detachesHiddenViews = true
        return view
    }()

    /// Keeps the language name and trailing controls centered during downloads.
    init(
        onAction: @escaping () -> Void
    ) {
        self.onAction = onAction
        super.init(color: Palette.surface, radius: 8)
        [language, rowControls].forEach(addSubview)
        snp.makeConstraints { make in
            make.height.equalTo(44)
        }
        language.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leading.equalToSuperview().inset(10)
            make.trailing.lessThanOrEqualTo(rowControls.snp.leading).offset(-12)
        }
        rowControls.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.trailing.equalToSuperview().inset(10)
            make.top.greaterThanOrEqualToSuperview().offset(6)
        }
        progress.snp.makeConstraints { make in
            make.width.equalTo(112)
            make.height.equalTo(10)
        }
        actionButton.snp.makeConstraints { make in
            make.width.equalTo(actionButton.preferredWidth)
            make.height.equalTo(24)
        }
    }

    /// Storyboard decoding is unsupported for this programmatic row.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Renders state changes without restarting a running indeterminate indicator.
    func update(
        _ row: GenerationTranslationViewModel.ResourceRow
    ) {
        if language.stringValue != row.language {
            language.stringValue = row.language
            language.toolTip = row.language
        }
        let downloadTitle = GenerationStrings.translationDownloadResource
        // Keep the existing action visible while the new language is checked.
        let keepsDownload = row.status == nil && !actionButton.isHidden && actionButton.title == downloadTitle
        let actionTitle = keepsDownload ? downloadTitle : row.actionTitle
        let hideStatus = row.statusTitle == nil || keepsDownload
        if status.isHidden != hideStatus { status.isHidden = hideStatus }
        if !hideStatus, let title = row.statusTitle, status.stringValue != title { status.stringValue = title }
        if keepsDownload, actionButton.disabledOpacity != 1 { actionButton.disabledOpacity = 1 }
        if actionButton.isEnabled != row.isActionEnabled { actionButton.isEnabled = row.isActionEnabled }
        if !keepsDownload, actionButton.disabledOpacity != 0.5 { actionButton.disabledOpacity = 0.5 }
        let hideAction = actionTitle == nil
        if actionButton.isHidden != hideAction { actionButton.isHidden = hideAction }
        if let action = actionTitle {
            if actionButton.title != action {
                actionButton.title = action
                actionButton.snp.updateConstraints { make in make.width.equalTo(actionButton.preferredWidth) }
            }
            let label = GenerationStrings.translationResourceAction(action, resource: row.language)
            if actionButton.accessibilityLabel() != label { actionButton.setAccessibilityLabel(label) }
        }

        guard case let .downloading(percent) = row.status else {
            if !progress.isHidden {
                progress.stopAnimation(nil)
                progress.isHidden = true
            }
            return
        }
        let indeterminate = percent == nil
        if progress.isHidden || progress.isIndeterminate != indeterminate {
            progress.stopAnimation(nil)
            progress.isIndeterminate = indeterminate
            progress.isHidden = false
            if indeterminate { progress.startAnimation(nil) }
        }
        if let percent { progress.doubleValue = Double(percent) }
    }
}
