//
//  HomeCameraControlsView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Factory
import AppKit

/// Native camera setup pills sharing the XLab header typography and button styling.
@MainActor
final class HomeCameraControlsView: Canvas {

    /// The session owner supplying physical camera choices and setup restrictions.
    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    /// The independent extension owner supplying installation and readiness state.
    @Injected(\.virtualCameraRepo) private var virtualCameraRepo: VirtualCameraRepository

    /// Opens physical camera selection after virtual-camera readiness is confirmed.
    private lazy var cameraButton: Button = {
        let view = Button(icon: .camera)
        view.font = Typography.font(size: 12)
        view.iconSize = 16
        view.chevron = true
        view.trailingPadding = 30
        view.setAccessibilityLabel("Select Camera")
        view.onClick = { [weak self] in self?.showCameras() }
        return view
    }()

    /// Opens the onboarding component's extension setup controls.
    private lazy var extensionButton: Button = {
        let view = Button("Virtual Camera")
        view.font = Typography.font(size: 12)
        view.iconSize = 16
        view.chevron = true
        view.trailingPadding = 30
        view.symbolName = "video.badge.checkmark"
        view.setAccessibilityLabel("Virtual Camera")
        view.onClick = { [weak self] in self?.showExtensionSettings() }
        return view
    }()

    /// The lazily created onboarding setup view with a host-owned diagnostic action.
    private lazy var settings: OnboardingSetupView = {
        let view = OnboardingSetupView()
        view.onTestVideo = { [weak self] in
            Task { [weak self] in await self?.generationRepo.toggleTestPattern() }
        }
        return view
    }()

    /// The transient popover currently owned by this component.
    private var popover: NSPopover?

    /// The currently presented dynamic device list, released when its popover closes.
    private var pickerContent: Canvas?

    /// The device-list identity used to avoid rebuilding unchanged picker rows.
    private var pickerSignature = ""

    /// Creates the camera-selection and onboarding entry points for the shared state owners.
    init() {
        super.init()
        [cameraButton, extensionButton].forEach(addSubview)
        update()
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// The camera pill width capped to keep long device names within the header.
    private var cameraWidth: CGFloat { min(150 + 16 + 8 + 14 + 30, cameraButton.preferredWidth) }

    /// The combined setup-control width including the gap between the pills.
    var preferredWidth: CGFloat { cameraWidth + 12 + extensionButton.preferredWidth }

    /// Receives the parent's coalesced state updates without rebuilding the setup controls.
    func update() {
        cameraButton.title = generationRepo.cameras.first { $0.id == generationRepo.cameraID }?.name ?? "Select Camera"
        cameraButton.toolTip = cameraButton.title
        cameraButton.isEnabled = !generationRepo.settingsLocked
        settings.update(
            settingsLocked: generationRepo.settingsLocked,
            testPatternActive: generationRepo.testPatternActive,
            isBusy: generationRepo.isBusy,
            sessionActive: generationRepo.sessionActive
        )
        if popover?.isShown == true, pickerContent == nil {
            popover?.contentSize = settings.frame.size
        }
        if popover?.isShown == true, pickerContent != nil {
            if generationRepo.settingsLocked { closePopover() } else { updateCameraPicker() }
        }
        needsLayout = true
    }

    /// Places the camera selection and virtual-camera setup pills on the same row.
    override func layout() {
        super.layout()
        cameraButton.frame = NSRect(
            x: 0,
            y: 0,
            width: cameraWidth,
            height: bounds.height
        )
        extensionButton.frame = NSRect(
            x: cameraWidth + 12,
            y: 0,
            width: extensionButton.preferredWidth,
            height: bounds.height
        )
    }

    /// Dismisses camera setup and releases its transient device-list view.
    func closePopover() {
        popover?.close()
        popover = nil
        pickerContent = nil
    }

    /// Presents a setup component using a native transient popover.
    private func present(
        _ content: NSView,
        from button: NSView
    ) {
        let viewController = NSViewController()
        viewController.view = content
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = viewController
        popover.contentSize = content.frame.size
        self.popover = popover
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .maxY
        )
    }

    /// Refreshes physical inputs or opens onboarding when the virtual camera is unavailable.
    private func showCameras() {
        guard !generationRepo.settingsLocked else { return }
        guard virtualCameraRepo.canStartSession else {
            showExtensionSettings()
            return
        }
        closePopover()
        generationRepo.refreshCameras()
        let content = Canvas()
        pickerContent = content
        pickerSignature = ""
        updateCameraPicker()
        present(
            content,
            from: cameraButton
        )
    }

    /// Rebuilds device choices only when their identity or selected device changes.
    private func updateCameraPicker() {
        guard let content = pickerContent else { return }
        let signature = generationRepo.cameraID + generationRepo.cameras.map { $0.id + $0.name }.joined(separator: "\n")
        guard signature != pickerSignature || content.subviews.isEmpty else { return }
        pickerSignature = signature
        content.subviews.forEach { $0.removeFromSuperview() }
        var y: CGFloat = 8
        for camera in generationRepo.cameras {
            let option = Button(
                camera.name + (camera.id == generationRepo.cameraID ? "  ✓" : ""),
                style: .tab
            )
            option.selected = camera.id == generationRepo.cameraID
            option.toolTip = camera.name
            option.frame = NSRect(
                x: 8,
                y: y,
                width: 260,
                height: 34
            )
            option.onClick = { [weak self] in
                guard let self, !self.generationRepo.settingsLocked else { return }
                self.generationRepo.cameraID = camera.id
                self.closePopover()
            }
            content.addSubview(option)
            y += 36
        }
        if generationRepo.cameras.isEmpty {
            let label = makeLabel(
                "No cameras found",
                size: 12,
                color: Palette.secondary
            )
            label.frame = NSRect(
                x: 16,
                y: y + 8,
                width: 244,
                height: 20
            )
            content.addSubview(label)
            y += 36
        }
        content.frame.size = NSSize(
            width: 276,
            height: y + 6
        )
        popover?.contentSize = content.frame.size
    }

    /// Opens the onboarding setup view and requests a fresh extension-state query.
    private func showExtensionSettings() {
        closePopover()
        settings.update(
            settingsLocked: generationRepo.settingsLocked,
            testPatternActive: generationRepo.testPatternActive,
            isBusy: generationRepo.isBusy,
            sessionActive: generationRepo.sessionActive
        )
        present(
            settings,
            from: extensionButton
        )
        virtualCameraRepo.refresh()
    }
}
