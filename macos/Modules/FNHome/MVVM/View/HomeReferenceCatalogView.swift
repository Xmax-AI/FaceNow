//
//  HomeReferenceCatalogView.swift
//  FaceNow
//

import AppKit
import Combine
import SnapKit

/// Presents the same categorized presets, uploads, and optional-image prompt flow as Windows.
@MainActor
final class HomeReferenceCatalogView: Canvas {

    private static let maximumCardWidth: CGFloat = 800
    private static let cardHeight: CGFloat = 436
    private static let preferredHorizontalMargins: CGFloat = 96
    private static let contentInset: CGFloat = 24
    private static let promptHeight: CGFloat = 168

    var onClose: (() -> Void)?
    var onUpload: ((GenerationMode) -> Void)?
    var onSelected: (() -> Void)?
    private let model: HomeReferenceViewModel
    private var category: GenerationMode
    private var observation: AnyCancellable?
    private var dismissalTask: Task<Void, Never>?
    private var isDismissing = false

    private lazy var backdrop: Canvas = {
        let view = Canvas(color: .black.withAlphaComponent(0.35))
        view.setAccessibilityElement(false)
        view.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(closeFromBackdrop)))
        return view
    }()

    private lazy var card: Canvas = {
        let view = Canvas(color: .white, radius: 16)
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowOpacity = 0.16
        view.layer?.shadowRadius = 24
        view.setAccessibilityRole(.group)
        view.setAccessibilityModal(true)
        view.setAccessibilityLabel(HomeStrings.referenceImages)
        return view
    }()

    private lazy var titleLabel: NSTextField = {
        let view = NSTextField(labelWithString: HomeStrings.referenceImages)
        view.font = .systemFont(ofSize: 22, weight: .semibold)
        view.textColor = Palette.text
        return view
    }()

    private lazy var closeButton: Button = {
        let view = Button(style: .plain)
        view.symbolName = "xmark"
        view.iconSize = 20
        view.centersSymbolVisually = true
        view.foregroundColor = Palette.secondary
        view.hoverBackgroundColor = Palette.surface
        view.cornerRadius = 10
        view.showsShadow = false
        view.keyEquivalent = "\u{1b}"
        view.keyEquivalentModifierMask = []
        view.setAccessibilityLabel(HomeStrings.closeReferenceImages)
        view.onClick = { [weak self] in self?.onClose?() }
        return view
    }()

    private lazy var categories: TabSwitcher = {
        let titles = GenerationMode.allCases.map(\.title)
        let view = TabSwitcher(titles: titles, distribution: .content)
        view.font = .systemFont(ofSize: 13.5, weight: .medium)
        view.onSelectionChanged = { [weak self] index in
            guard let self else { return }
            self.category = GenerationMode.allCases[index]
            self.update(resetScroll: true)
        }
        return view
    }()

    private lazy var body: Canvas = {
        let view = Canvas()
        return view
    }()

    private lazy var references: GenerationReferenceListView = {
        let view = GenerationReferenceListView()
        view.onSelect = { [weak self] reference in
            guard let self, self.model.canEdit else { return }
            self.model.select(reference)
            self.onSelected?()
        }
        view.onUpload = { [weak self] in
            guard let self else { return }
            self.onUpload?(self.category)
        }
        return view
    }()

    private lazy var promptSurface: Canvas = {
        let view = Canvas(color: Palette.surface, radius: 18)
        view.layer?.borderColor = Palette.border.cgColor
        view.layer?.borderWidth = 1
        return view
    }()

    private lazy var promptScroll: NSScrollView = {
        let view = NSScrollView()
        view.drawsBackground = false
        view.hasVerticalScroller = true
        view.scrollerStyle = .overlay
        view.documentView = promptEditor
        return view
    }()

    private lazy var promptEditor: GenerationPromptTextView = {
        let view = GenerationPromptTextView()
        view.font = .systemFont(ofSize: 15)
        view.textColor = Palette.text
        view.drawsBackground = false
        view.isRichText = false
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.placeholder = GenerationStrings.controlsDescribeHowYouWantTheVideoToChange
        view.string = model.prompt
        view.setAccessibilityLabel(GenerationMode.free.title)
        view.onCommittedTextChange = { [weak self] text in
            guard let self else { return }
            self.model.prompt = text
        }
        return view
    }()

    private lazy var upload: GenerationReferenceButton = {
        let view = GenerationReferenceButton()
        view.compactThumbnailSize = 44
        view.onClick = { [weak self] in self?.onUpload?(.free) }
        return view
    }()

    private lazy var remove: Button = {
        let view = Button(style: .dismiss)
        view.symbolName = "xmark"
        view.iconSize = 10
        view.centersSymbolVisually = true
        view.showsShadow = false
        view.setAccessibilityLabel(GenerationStrings.controlsRemoveReference)
        view.onClick = { [weak self] in self?.model.removeFreeReference() }
        return view
    }()

    private lazy var submit: Button = {
        let view = Button(style: .primary)
        view.symbolName = "arrow.up"
        view.iconSize = 20
        view.centersSymbolVisually = true
        view.cornerRadius = 22
        view.showsShadow = false
        view.setAccessibilityLabel(GenerationStrings.controlsSubmitPrompt)
        view.toolTip = GenerationStrings.controlsSubmitPrompt
        view.onClick = { [weak self] in
            guard let self, self.model.submitPrompt() else { return }
            self.onSelected?()
        }
        return view
    }()

    private lazy var errorLabel: NSTextField = {
        let view = NSTextField(wrappingLabelWithString: "")
        view.font = .systemFont(ofSize: 12)
        view.textColor = Palette.destructive
        view.maximumNumberOfLines = 2
        return view
    }()

    override var acceptsFirstResponder: Bool { true }

    init(model: HomeReferenceViewModel) {
        self.model = model
        self.category = model.selected.mode
        super.init()
        [backdrop, card].forEach { addSubview($0) }
        [titleLabel, closeButton, categories, body, errorLabel].forEach { card.addSubview($0) }
        [references, promptSurface].forEach { body.addSubview($0) }
        [promptScroll, upload, remove, submit].forEach { promptSurface.addSubview($0) }
        configureLayout()
        backdrop.layer?.opacity = 0
        card.layer?.opacity = 0
        categories.selectedIndex = GenerationMode.allCases.firstIndex(of: category)
        observation = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.update() }
        }
        setAccessibilityRole(.group)
        setAccessibilityChildren([card])
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        ControlMotion.setModalVisible(true, backdrop: backdrop, card: card, in: self) {}
        update()
        window?.makeFirstResponder(closeButton)
    }

    func dismiss(animated: Bool, completion: @escaping @MainActor () -> Void) {
        guard !isDismissing || !animated else { return }
        dismissalTask?.cancel()
        isDismissing = true
        window?.makeFirstResponder(self)
        guard animated, ControlMotion.isAnimated(in: self) else { completion(); return }
        ControlMotion.setModalVisible(false, backdrop: backdrop, card: card, in: self) {}
        dismissalTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(ControlMotion.duration)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.dismissalTask = nil
            completion()
        }
    }

    func shutdown() {
        dismissalTask?.cancel()
        dismissalTask = nil
        observation = nil
        references.suspendImages()
        upload.thumbnail.cancel()
    }

    private func update(resetScroll: Bool = false) {
        guard !isDismissing else { return }
        categories.isEnabled = model.canEdit
        let free = category == .free
        references.isHidden = free
        promptSurface.isHidden = !free
        references.update(
            references: model.catalog(for: category),
            selectedID: model.selected.id,
            enabled: model.canEdit,
            dimmed: false,
            resetScroll: resetScroll
        )
        promptEditor.isEditable = model.canEdit
        submit.isEnabled = model.canSubmitPrompt
        let pending = model.pending.flatMap { $0.mode == .free ? $0 : nil }
        upload.configure(pending ?? model.freeReference, selected: false, enabled: model.canEdit)
        remove.isHidden = model.freeReference == nil
        remove.isEnabled = model.canEdit
        errorLabel.stringValue = model.error ?? ""
        errorLabel.toolTip = model.error
        let showsError = !errorLabel.stringValue.isEmpty
        if errorLabel.isHidden == showsError {
            errorLabel.isHidden = !showsError
            errorLabel.snp.updateConstraints { make in make.height.equalTo(showsError ? 30 : 0) }
            body.snp.updateConstraints { make in make.bottom.equalTo(errorLabel.snp.top).offset(showsError ? -12 : 0) }
        }
        var focusOrder: [NSView] = [closeButton] + categories.selectionControls
        if free {
            focusOrder += [promptEditor, upload]
            if model.freeReference != nil { focusOrder.append(remove) }
            focusOrder.append(submit)
        } else {
            focusOrder += references.focusControls
        }
        for (index, control) in focusOrder.enumerated() {
            control.nextKeyView = focusOrder[(index + 1) % focusOrder.count]
        }
    }

    private func configureLayout() {
        backdrop.snp.makeConstraints { make in make.edges.equalToSuperview() }
        card.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().inset(24)
            make.trailing.lessThanOrEqualToSuperview().inset(24)
            make.top.greaterThanOrEqualToSuperview().inset(24)
            make.bottom.lessThanOrEqualToSuperview().inset(24)
            make.width.equalToSuperview().offset(-Self.preferredHorizontalMargins).priority(490)
            make.width.lessThanOrEqualTo(Self.maximumCardWidth)
            make.height.equalTo(Self.cardHeight).priority(490)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(24)
            make.trailing.lessThanOrEqualTo(closeButton.snp.leading).offset(-12)
        }
        closeButton.snp.makeConstraints { make in
            make.top.trailing.equalToSuperview().inset(12)
            make.size.equalTo(40)
        }
        categories.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(18)
            make.centerX.equalToSuperview()
            make.width.lessThanOrEqualToSuperview().offset(-2 * Self.contentInset)
            make.width.equalTo(categories.preferredWidth).priority(490)
            make.height.equalTo(42)
        }
        body.snp.makeConstraints { make in
            make.top.equalTo(categories.snp.bottom).offset(18)
            make.leading.trailing.equalToSuperview().inset(Self.contentInset)
            make.bottom.equalTo(errorLabel.snp.top)
        }
        references.snp.makeConstraints { make in make.edges.equalToSuperview() }
        promptSurface.snp.makeConstraints { make in
            make.leading.top.trailing.equalToSuperview()
            make.height.equalTo(Self.promptHeight)
        }
        promptScroll.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(18)
            make.height.equalTo(78)
        }
        promptEditor.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(promptScroll.contentView)
            make.height.greaterThanOrEqualTo(promptScroll.contentView)
        }
        submit.snp.makeConstraints { make in
            make.trailing.bottom.equalToSuperview().inset(12)
            make.size.equalTo(44)
        }
        upload.snp.makeConstraints { make in
            make.trailing.equalTo(submit.snp.leading).offset(-10)
            make.centerY.equalTo(submit)
            make.size.equalTo(44)
        }
        remove.snp.makeConstraints { make in
            make.centerX.equalTo(upload.snp.trailing).offset(-4)
            make.centerY.equalTo(upload.snp.top).offset(4)
            make.size.equalTo(18)
        }
        errorLabel.snp.makeConstraints { make in
            make.leading.trailing.equalTo(body)
            make.bottom.equalToSuperview().inset(24)
            make.height.equalTo(0)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(convert(point, from: superview)) else { return nil }
        return isDismissing ? self : super.hitTest(point) ?? self
    }

    override func mouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func cancelOperation(_ sender: Any?) { onClose?() }
    @objc private func closeFromBackdrop() { if !isDismissing { onClose?() } }
}
