//
//  HomeCameraPickerView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import Factory
import SnapKit

/// Selects the physical camera beneath the landing page's Start Camera action.
@MainActor
final class HomeCameraPickerView: Canvas {

    /// Opens camera preparation only after the user requests an unavailable selector.
    var onShowCameraSetup: (() -> Void)?

    /// Supplies the discovered camera list and shared input selection.
    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    /// Checks permission and discovers inputs without opening a capture stream.
    @Injected(\.virtualCameraRepo) private var virtualCameraRepo: VirtualCameraRepository

    /// The translucent capsule retains the original microphone control's compact styling.
    private lazy var button: ToolbarButton = {
        let view = ToolbarButton(
            style: .plain,
            chevron: true
        )
        view.font = Typography.font(size: 13)
        view.leadingPadding = 16
        view.foregroundColor = .white.withAlphaComponent(0.85)
        view.hoverBackgroundColor = .white.withAlphaComponent(0.08)
        view.cornerRadius = 16
        view.showsShadow = false
        view.setAccessibilityLabel(HomeStrings.homeSelectCamera)
        view.onClick = { [weak self] in self?.showCameraPicker() }
        return view
    }()

    /// Retains the transient camera list until its trigger or owning page dismisses it.
    private var cameraPopover: NSPopover?

    /// Identifies device-list changes while a popover presents an earlier snapshot.
    private var cameraSignature = ""

    /// Builds a stable native trigger without starting camera capture.
    init() {
        super.init(color: .black.withAlphaComponent(0.28), radius: 16)
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        addSubview(button)
        button.snp.makeConstraints { make in make.edges.equalToSuperview() }
        update()
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Caps long device names while preserving the complete name in the list and tooltip.
    override var intrinsicContentSize: NSSize {
        NSSize(width: min(280, button.preferredWidth), height: 32)
    }

    /// Reflects repository selection without retaining an independent selected camera.
    func update() {
        let signature = generationRepo.cameraID + generationRepo.cameras.map { $0.id + $0.name }.joined()
        if signature != cameraSignature {
            cameraSignature = signature
            closeCameraPicker()
        }
        let title =
            generationRepo.cameras.first { $0.id == generationRepo.cameraID }?.name
            ?? HomeStrings.homeSelectCamera
        if button.title != title {
            button.title = title
            invalidateIntrinsicContentSize()
        }
        button.toolTip = title
        button.setAccessibilityValue(title)
        button.isEnabled = !generationRepo.settingsLocked && !generationRepo.isClosing
        if !button.isEnabled || !virtualCameraRepo.canStartSession { closeCameraPicker() }
    }

    /// Opens current physical choices or routes missing permission to the existing setup flow.
    func showCameraPicker() {
        if cameraPopover?.isShown == true {
            closeCameraPicker()
            return
        }
        guard !generationRepo.settingsLocked, !generationRepo.isClosing, window != nil, !isHiddenOrHasHiddenAncestor
        else { return }
        virtualCameraRepo.synchronizeReadiness()
        guard virtualCameraRepo.canStartSession else {
            onShowCameraSetup?()
            return
        }
        virtualCameraRepo.prepareCameraInputs()
        generationRepo.refreshCameras()
        update()
        let content = HomeCameraPickerPopoverView(
            cameras: generationRepo.cameras,
            selectedID: generationRepo.cameraID,
            onSelect: { [weak self] id in self?.selectCamera(id) }
        )
        let controller = NSViewController()
        controller.view = content
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = controller
        popover.contentSize = content.fittingSize
        cameraPopover = popover
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .maxY
        )
    }

    /// Releases the list before the trigger is covered or detached.
    func closeCameraPicker() {
        cameraPopover?.close()
        cameraPopover = nil
    }

    /// Dismisses the list when the landing page yields to generation or login.
    override func viewDidHide() {
        super.viewDidHide()
        closeCameraPicker()
    }

    /// Dismisses the list when the containing page leaves its window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { closeCameraPicker() }
    }

    /// Rejects stale or locked choices before committing the shared physical input.
    private func selectCamera(
        _ id: String
    ) {
        guard !generationRepo.settingsLocked, !generationRepo.isClosing, virtualCameraRepo.canStartSession,
            generationRepo.cameras.contains(where: { $0.id == id })
        else { return }
        closeCameraPicker()
        generationRepo.cameraID = id
        update()
    }
}

/// Matches the account popover's white surface, compact rows, and rounded hover fills.
@MainActor
private final class HomeCameraPickerPopoverView: Canvas {

    /// Keeps larger camera lists inside a compact popover without clipping choices.
    private lazy var scroll: NSScrollView = {
        let view = NSScrollView()
        view.drawsBackground = false
        view.borderType = .noBorder
        view.hasVerticalScroller = true
        view.autohidesScrollers = true
        return view
    }()

    /// Arranges native camera actions with the account menu's row spacing.
    private lazy var list: NSStackView = {
        let view = NSStackView()
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 2
        return view
    }()

    /// Presents a device snapshot while leaving camera selection in the shared repository.
    init(
        cameras: [GenerationRepository.CaptureDevice],
        selectedID: String,
        onSelect: @escaping (String) -> Void
    ) {
        super.init(
            color: .white,
            radius: 16
        )
        layer?.masksToBounds = true
        let choices =
            cameras.isEmpty
            ? [GenerationRepository.CaptureDevice(id: "", name: HomeStrings.homeNoCamerasFound)] : cameras
        let rows = choices.map { camera in
            let selected = !cameras.isEmpty && camera.id == selectedID
            let row = Button(
                camera.name,
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
            row.isEnabled = !cameras.isEmpty
            row.toolTip = camera.name
            row.setAccessibilityValue(selected)
            row.onClick = { onSelect(camera.id) }
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
            make.height.equalTo(min(286, listHeight) + 20)
        }
        scroll.snp.makeConstraints { make in make.edges.equalToSuperview().inset(10) }
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
