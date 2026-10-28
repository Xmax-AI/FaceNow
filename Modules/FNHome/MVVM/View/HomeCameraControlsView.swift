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
import AVFoundation
import SnapKit

/// Native camera setup pills sharing the XLab header typography and button styling.
@MainActor
final class HomeCameraControlsView: Canvas {

    /// Opens the preparation flow at a missing requirement or its first incomplete stage.
    var onShowOnboarding: ((OnboardingRepository.Step?) -> Void)?

    /// Reopens the preparation guide immediately to the left of physical camera selection.
    private lazy var guideButton: Button = {
        let view = Button("Setup Guide")
        view.symbolName = "questionmark.circle"
        view.font = Typography.font(size: 12)
        view.iconSize = 15
        view.toolTip = "How to use FaceNow in video calls"
        view.setAccessibilityLabel("Open FaceNow setup guide")
        view.onClick = { [weak self] in self?.onShowOnboarding?(nil) }
        return view
    }()

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
        [guideButton, cameraButton, extensionButton].forEach(addSubview)
        guideButton.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.equalTo(guideButton.preferredWidth)
        }
        cameraButton.snp.makeConstraints { make in
            make.leading.equalTo(guideButton.snp.trailing).offset(12)
            make.top.bottom.equalToSuperview()
            make.width.equalTo(cameraWidth)
        }
        extensionButton.snp.makeConstraints { make in
            make.leading.equalTo(cameraButton.snp.trailing).offset(12)
            make.top.bottom.trailing.equalToSuperview()
        }
        update()
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// The camera pill width capped to keep long device names within the header.
    private var cameraWidth: CGFloat { min(150 + 16 + 8 + 14 + 30, cameraButton.preferredWidth) }

    /// The combined setup-control width including the gap between the pills.
    var preferredWidth: CGFloat { guideButton.preferredWidth + 12 + cameraWidth + 12 + extensionButton.preferredWidth }

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
            popover?.contentSize = settings.intrinsicContentSize
        }
        if popover?.isShown == true, pickerContent != nil {
            if generationRepo.settingsLocked { closePopover() } else { updateCameraPicker() }
        }
        needsLayout = true
    }

    /// Places the camera selection and virtual-camera setup pills on the same row.
    override func layout() {
        cameraButton.snp.updateConstraints { make in make.width.equalTo(cameraWidth) }
        super.layout()
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
        popover.contentSize = content.fittingSize
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
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            onShowOnboarding?(.camera)
            return
        }
        guard virtualCameraRepo.canStartSession else {
            onShowOnboarding?(.virtualCamera)
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
        var previous: NSView?
        for camera in generationRepo.cameras {
            let option = Button(
                camera.name + (camera.id == generationRepo.cameraID ? "  ✓" : ""),
                style: .tab
            )
            option.selected = camera.id == generationRepo.cameraID
            option.toolTip = camera.name
            option.onClick = { [weak self] in
                guard let self, !self.generationRepo.settingsLocked else { return }
                self.generationRepo.cameraID = camera.id
                self.closePopover()
            }
            content.addSubview(option)
            option.snp.makeConstraints { make in
                make.leading.trailing.equalToSuperview().inset(8)
                make.height.equalTo(34)
                if let previous {
                    make.top.equalTo(previous.snp.bottom).offset(2)
                } else {
                    make.top.equalToSuperview().offset(8)
                }
            }
            previous = option
        }
        if previous == nil {
            let label = makeLabel("No cameras found", size: 12, color: Palette.secondary)
            content.addSubview(label)
            label.snp.makeConstraints { make in
                make.leading.trailing.equalToSuperview().inset(16)
                make.top.equalToSuperview().offset(16)
                make.height.equalTo(20)
            }
            previous = label
        }
        previous?.snp.makeConstraints { make in make.bottom.equalToSuperview().inset(8) }
        content.snp.remakeConstraints { make in make.width.equalTo(276) }
        popover?.contentSize = content.fittingSize
    }

    /// Opens the onboarding setup view and requests a fresh extension-state query.
    private func showExtensionSettings() {
        if !virtualCameraRepo.canStartSession, onShowOnboarding != nil {
            closePopover()
            onShowOnboarding?(.virtualCamera)
            return
        }
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
