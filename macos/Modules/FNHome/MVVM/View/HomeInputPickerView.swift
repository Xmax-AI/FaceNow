//
//  HomeInputPickerView.swift
//  FaceNow
//

import AppKit
import Factory
import SnapKit

/// Selects camera or microphone input beneath the landing page's Start Camera action.
@MainActor
final class HomeInputPickerView: Canvas, NSPopoverDelegate {

    /// The input capability represented by this selector.
    enum Input {
        /// Captures local video through the existing camera readiness flow.
        case camera

        /// Configures audio input without opening capture in the picker.
        case microphone
    }

    /// The surface hosting the input selector.
    enum Presentation {
        /// A translucent control over the landing checkerboard.
        case landing

        /// A standard capsule in the generation page's white audio toolbar.
        case toolbar
    }

    /// The fixed surface styling and sizing of the selector.
    private let presentation: Presentation

    /// Whether the repository currently accepts changes to this input capability.
    private var canSelect: Bool {
        input == .microphone
            ? generationRepo.canChangeMicrophone
            : !generationRepo.settingsLocked && !generationRepo.isClosing
    }

    /// The input capability whose selection and choices this view presents.
    private let input: Input

    /// Hides cached device names until this input has system permission.
    private var hasInputAccess: Bool {
        input == .camera
            ? virtualCameraRepo.canStartSession
            : generationRepo.microphoneAuthorization == .authorized
    }

    /// The concrete input devices followed by the disabled microphone option.
    private var devices: [GenerationRepository.CaptureDevice] {
        guard hasInputAccess else { return [] }
        if input == .camera { return generationRepo.cameras }
        return generationRepo.microphones + [
            .init(id: GenerationRepository.disabledMicrophoneID, name: HomeStrings.microphoneOff)
        ]
    }

    /// The shared selection owned by the generation repository.
    private var selectedID: String {
        input == .camera ? generationRepo.cameraID : generationRepo.microphoneID
    }

    /// Opens camera preparation only after the user requests an unavailable selector.
    var onShowCameraSetup: (() -> Void)?

    /// Opens microphone-permission guidance through the shared home coordinator.
    var onShowMicrophoneSetup: (() -> Void)?

    /// Supplies discovered inputs and their shared selection.
    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    /// Checks permission and discovers inputs without opening a capture stream.
    @Injected(\.virtualCameraRepo) private var virtualCameraRepo: VirtualCameraRepository

    /// The translucent capsule matches the compact input controls beneath Start Camera.
    private lazy var button: Button = {
        let view = Button(style: presentation == .toolbar ? .pill : .plain)
        view.chevron = true
        view.configureForToolbar(weight: .regular)
        view.font =
            presentation == .toolbar
            ? .systemFont(ofSize: ToolbarControlMetrics.fontSize, weight: .semibold) : Typography.font(size: 13)
        view.leadingPadding = 16
        if presentation == .toolbar {
            view.style = .plain
            view.foregroundColor = Palette.softText
            view.restingBackgroundColor = Palette.accent.withAlphaComponent(0.12)
            view.hoverBackgroundColor = Palette.accent.withAlphaComponent(0.18)
            view.leadingPadding = 40
            view.trailingPadding = 44
            view.alignment = .left
            view.centersTitleVisually = true
        } else {
            view.foregroundColor = Palette.videoControlText
            view.hoverBackgroundColor = Palette.videoControlHover
        }
        view.cornerRadius = 16
        view.showsShadow = false
        view.onClick = { [weak self] in self?.showPicker() }
        return view
    }()

    /// Allows a containing dialog to include the selector in its keyboard loop.
    var focusControl: NSView { button }

    /// Separates the microphone glyph and disclosure region without intercepting button input.
    private lazy var toolbarDecoration: HomeInputPickerToolbarDecoration = {
        let view = HomeInputPickerToolbarDecoration()
        return view
    }()

    /// Retains the transient input list until its trigger or owning page dismisses it.
    private var inputPopover: NSPopover?

    /// Identifies device-list changes while a popover presents an earlier snapshot.
    private var inputSignature = ""

    /// Keeps device refresh attached to the visible selector's lifetime.
    private var pickerTask: Task<Void, Never>?

    /// Cancels a view-owned selection request when its containing page is removed or hidden.
    private var selectionTask: Task<Void, Never>?

    /// Builds a stable native trigger without starting camera capture.
    init(
        input: Input = .camera,
        presentation: Presentation = .landing
    ) {
        self.input = input
        self.presentation = presentation
        super.init(color: presentation == .landing ? Palette.videoControlSurface : .clear, radius: 16)
        if presentation == .landing {
            layer?.borderWidth = 1
            layer?.borderColor = Palette.videoControlBorder.cgColor
        }
        addSubview(button)
        button.snp.makeConstraints { make in make.edges.equalToSuperview() }
        if presentation == .toolbar {
            button.addSubview(toolbarDecoration)
            toolbarDecoration.snp.makeConstraints { make in make.edges.equalToSuperview() }
        }
        update()
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Caps long device names while preserving the complete name in the list and tooltip.
    override var intrinsicContentSize: NSSize {
        NSSize(
            width: min(280, button.preferredWidth),
            height: presentation == .toolbar ? ToolbarControlMetrics.compactHeight : 32
        )
    }

    /// Reflects repository selection without retaining independent input state.
    func update() {
        if input == .microphone { generationRepo.synchronizeMicrophoneAuthorization() }
        let signature = selectedID + devices.map { $0.id + $0.name }.joined()
        if signature != inputSignature {
            inputSignature = signature
            if let popover = inputPopover, popover.isShown {
                let content = HomeInputPickerPopoverView(
                    devices: devices,
                    selectedID: selectedID,
                    onSelect: { [weak self] id in self?.selectDevice(id) }
                )
                let controller = NSViewController()
                controller.view = content
                popover.contentViewController = controller
                popover.contentSize = content.fittingSize
            }
        }
        let selectionTitle = input == .camera ? HomeStrings.homeSelectCamera : HomeStrings.selectMicrophone
        let authorizationTitle = input == .camera ? HomeStrings.authorizeCamera : HomeStrings.authorizeMicrophone
        let title = hasInputAccess ? devices.first { $0.id == selectedID }?.name ?? selectionTitle : authorizationTitle
        if button.title != title {
            button.title = title
            invalidateIntrinsicContentSize()
        }
        button.toolTip = title
        button.setAccessibilityLabel(hasInputAccess ? selectionTitle : authorizationTitle)
        button.setAccessibilityValue(title)
        button.isEnabled = canSelect
        if presentation == .toolbar {
            toolbarDecoration.update(
                disabled: selectedID == GenerationRepository.disabledMicrophoneID
            )
        }
        if inputPopover != nil, !button.isEnabled || !hasInputAccess { closePicker() }
    }

    /// Opens current input choices or focused guidance when the input needs permission.
    func showPicker() {
        if inputPopover?.isShown == true {
            closePicker()
            return
        }
        guard canSelect, window != nil, !isHiddenOrHasHiddenAncestor
        else { return }
        if input == .camera {
            virtualCameraRepo.synchronizeReadiness()
            guard virtualCameraRepo.canStartSession else {
                onShowCameraSetup?()
                return
            }
            virtualCameraRepo.prepareCameraInputs()
            generationRepo.refreshCameras()
        } else {
            generationRepo.synchronizeMicrophoneAuthorization()
            guard hasInputAccess else {
                onShowMicrophoneSetup?()
                return
            }
            guard pickerTask == nil else { return }
            pickerTask = Task { [weak self] in
                guard let self else { return }
                defer {
                    pickerTask = nil
                    update()
                }
                guard !Task.isCancelled, canSelect, window != nil, !isHiddenOrHasHiddenAncestor else { return }
                await generationRepo.refreshMicrophones()?.value
                guard !Task.isCancelled else { return }
                presentPicker()
            }
            return
        }
        presentPicker()
    }

    /// Presents authorized choices only while the selector is still visible and interactive.
    private func presentPicker() {
        guard canSelect, hasInputAccess, window != nil, !isHiddenOrHasHiddenAncestor else { return }
        update()
        let content = HomeInputPickerPopoverView(
            devices: devices,
            selectedID: selectedID,
            onSelect: { [weak self] id in self?.selectDevice(id) }
        )
        let controller = NSViewController()
        controller.view = content
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = controller
        popover.delegate = self
        popover.contentSize = content.fittingSize
        inputPopover = popover
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .maxY
        )
    }

    /// Releases the list before the trigger is covered or detached.
    func closePicker() {
        pickerTask?.cancel()
        inputPopover?.close()
        inputPopover = nil
    }

    /// Releases a natively dismissed device list.
    func popoverDidClose(
        _ notification: Notification
    ) {
        guard let popover = notification.object as? NSPopover, inputPopover === popover else { return }
        inputPopover = nil
    }

    /// Dismisses the list when the landing page yields to generation or login.
    override func viewDidHide() {
        super.viewDidHide()
        selectionTask?.cancel()
        selectionTask = nil
        closePicker()
    }

    /// Dismisses the list when the containing page leaves its window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            selectionTask?.cancel()
            selectionTask = nil
            closePicker()
        }
    }

    /// Rejects stale or locked choices before committing the shared input.
    private func selectDevice(
        _ id: String
    ) {
        guard canSelect,
            input != .camera || virtualCameraRepo.canStartSession,
            devices.contains(where: { $0.id == id })
        else { return }
        closePicker()
        if input == .camera {
            generationRepo.cameraID = id
        } else {
            selectionTask = Task { [weak self] in
                guard let self else { return }
                await generationRepo.selectMicrophone(id)
                update()
                selectionTask = nil
            }
        }
        update()
    }
}

/// Aligns the tinted microphone glyph and divider on the selector's shared vertical center.
@MainActor
private final class HomeInputPickerToolbarDecoration: Canvas {

    /// Identifies microphone input independently of the neutral title color.
    private lazy var glyph: NSImageView = {
        let view = NSImageView()
        view.symbolConfiguration = .init(pointSize: 16, weight: .regular)
        view.contentTintColor = Palette.accent
        return view
    }()

    /// Separates the selected capability from the disclosure arrow.
    private lazy var separator: Canvas = {
        let view = Canvas(color: Palette.secondary.withAlphaComponent(0.5))
        return view
    }()

    /// Installs fixed decorative geometry inside the native button's hit area.
    init() {
        super.init()
        [glyph, separator].forEach(addSubview)
        glyph.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.size.equalTo(ToolbarControlMetrics.iconSize)
        }
        separator.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(34)
            make.centerY.equalToSuperview()
            make.width.equalTo(1)
            make.height.equalTo(16)
        }
        setAccessibilityElement(false)
    }

    /// Storyboard decoding is unsupported for this decorative view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Keeps pointer events on the native selector beneath the decoration.
    override func hitTest(
        _ point: NSPoint
    ) -> NSView? { nil }

    /// Reflects input intent while the containing button owns disabled-opacity animation.
    func update(
        disabled: Bool
    ) {
        glyph.image = NSImage(systemSymbolName: disabled ? "mic.slash" : "mic", accessibilityDescription: nil)
    }
}

/// Matches the account popover's white surface, compact rows, and rounded hover fills.
@MainActor
private final class HomeInputPickerPopoverView: Canvas {

    /// Keeps larger device lists inside a compact popover without clipping choices.
    private lazy var scroll: NSScrollView = {
        let view = NSScrollView()
        view.drawsBackground = false
        view.borderType = .noBorder
        view.hasVerticalScroller = true
        view.autohidesScrollers = true
        return view
    }()

    /// Arranges native input actions with the account menu's row spacing.
    private lazy var list: NSStackView = {
        let view = NSStackView()
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 2
        return view
    }()

    /// Presents a device snapshot while leaving input selection in the shared repository.
    init(
        devices: [GenerationRepository.CaptureDevice],
        selectedID: String,
        onSelect: @escaping (String) -> Void
    ) {
        super.init(
            color: .white,
            radius: 16
        )
        layer?.masksToBounds = true
        let choices =
            devices.isEmpty
            ? [GenerationRepository.CaptureDevice(id: "", name: HomeStrings.homeNoCamerasFound)] : devices
        let rows = choices.map { device in
            let selected = !devices.isEmpty && device.id == selectedID
            let row = Button(
                device.name,
                style: .plain
            )
            row.font = Typography.font(size: 13)
            row.alignment = .left
            row.foregroundColor = Palette.secondary
            row.hoverBackgroundColor = Palette.surface
            row.cornerRadius = 12
            row.showsShadow = false
            row.symbolName = selected ? "checkmark" : nil
            row.iconSize = 16
            row.iconSpacing = 10
            row.leadingPadding = selected ? 12 : 38
            row.trailingPadding = 12
            row.isEnabled = !devices.isEmpty
            row.toolTip = device.name
            row.setAccessibilityValue(selected)
            row.onClick = { onSelect(device.id) }
            return row
        }
        addSubview(scroll)
        scroll.documentView = list
        rows.forEach { row in
            list.addArrangedSubview(row)
            row.snp.makeConstraints { make in
                make.width.equalToSuperview()
                make.height.equalTo(34)
            }
        }
        let listHeight = CGFloat(rows.count) * 36 - 2
        let width = min(340, max(220, (rows.map(\.preferredWidth).max() ?? 0) + 20))
        snp.makeConstraints { make in
            make.width.equalTo(width)
        }
        scroll.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(10)
            make.height.equalTo(min(286, listHeight))
        }
        list.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(scroll.contentView)
            make.height.equalTo(listHeight)
        }
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }
}
