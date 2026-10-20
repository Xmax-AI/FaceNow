//
//  CameraHomeControls.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit

/// Native camera setup pills sharing the XLab header typography and button styling.
@MainActor
final class CameraHomeControls: RealtimeCanvas {
    private let controller: CameraSessionController
    private let cameraExtension: CameraExtensionController
    private let cameraButton = RealtimeButton(icon: .camera)
    private let extensionButton = RealtimeButton("Virtual Camera")
    private lazy var settings = CameraExtensionSettings(controller: controller, cameraExtension: cameraExtension)
    private var popover: NSPopover?
    private var pickerContent: RealtimeCanvas?
    private var pickerSignature = ""

    init(controller: CameraSessionController, cameraExtension: CameraExtensionController) {
        self.controller = controller
        self.cameraExtension = cameraExtension
        super.init()
        for button in [cameraButton, extensionButton] {
            button.font = RealtimeHeaderTypography.font(size: 12)
            button.iconSize = 16
            button.chevron = true
            button.trailingPadding = 30
            addSubview(button)
        }
        cameraButton.setAccessibilityLabel("Select Camera")
        extensionButton.symbolName = "video.badge.checkmark"
        extensionButton.setAccessibilityLabel("Virtual Camera")
        cameraButton.onClick = { [weak self] in self?.showCameras() }
        extensionButton.onClick = { [weak self] in self?.showExtensionSettings() }
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var cameraWidth: CGFloat { min(150 + 16 + 8 + 14 + 30, cameraButton.preferredWidth) }
    var preferredWidth: CGFloat { cameraWidth + 12 + extensionButton.preferredWidth }

    /// Receives the parent's coalesced state updates without rebuilding the setup controls.
    func update() {
        cameraButton.title = controller.cameras.first { $0.id == controller.cameraID }?.name ?? "Select Camera"
        cameraButton.toolTip = cameraButton.title
        cameraButton.isEnabled = !controller.settingsLocked
        settings.update()
        if popover?.isShown == true, pickerContent == nil {
            popover?.contentSize = settings.frame.size
        }
        if popover?.isShown == true, pickerContent != nil {
            if controller.settingsLocked { closePopover() }
            else { updateCameraPicker() }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        cameraButton.frame = NSRect(x: 0, y: 0, width: cameraWidth, height: bounds.height)
        extensionButton.frame = NSRect(x: cameraWidth + 12, y: 0, width: extensionButton.preferredWidth, height: bounds.height)
    }

    func closePopover() {
        popover?.close()
        popover = nil
        pickerContent = nil
    }

    private func present(_ content: NSView, from button: NSView) {
        let viewController = NSViewController()
        viewController.view = content
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = viewController
        popover.contentSize = content.frame.size
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
    }

    private func showCameras() {
        guard !controller.settingsLocked else { return }
        closePopover()
        let content = RealtimeCanvas()
        pickerContent = content
        pickerSignature = ""
        updateCameraPicker()
        present(content, from: cameraButton)
    }

    private func updateCameraPicker() {
        guard let content = pickerContent else { return }
        let signature = controller.cameraID + controller.cameras.map { $0.id + $0.name }.joined(separator: "\n")
        guard signature != pickerSignature || content.subviews.isEmpty else { return }
        pickerSignature = signature
        content.subviews.forEach { $0.removeFromSuperview() }
        var y: CGFloat = 8
        for camera in controller.cameras {
            let option = RealtimeButton(camera.name + (camera.id == controller.cameraID ? "  ✓" : ""), style: .tab)
            option.selected = camera.id == controller.cameraID
            option.toolTip = camera.name
            option.frame = NSRect(x: 8, y: y, width: 260, height: 34)
            option.onClick = { [weak self] in
                guard let self, !self.controller.settingsLocked else { return }
                self.controller.cameraID = camera.id
                self.closePopover()
            }
            content.addSubview(option)
            y += 36
        }
        if controller.cameras.isEmpty {
            let label = realtimeLabel("No cameras found", size: 12, color: RealtimePalette.secondary)
            label.frame = NSRect(x: 16, y: y + 8, width: 244, height: 20)
            content.addSubview(label)
            y += 36
        }
        let separator = NSBox(); separator.boxType = .separator
        separator.frame = NSRect(x: 8, y: y + 4, width: 260, height: 1)
        content.addSubview(separator)
        let refresh = RealtimeButton("Refresh Cameras", style: .tab)
        refresh.frame = NSRect(x: 8, y: y + 10, width: 260, height: 34)
        refresh.onClick = { [weak self] in self?.controller.refreshCameras() }
        content.addSubview(refresh)
        content.frame.size = NSSize(width: 276, height: y + 52)
        popover?.contentSize = content.frame.size
    }

    private func showExtensionSettings() {
        closePopover()
        settings.update()
        present(settings, from: extensionButton)
        cameraExtension.refresh()
    }
}

/// Persistent extension installation controls, updated independently of the session page.
@MainActor
private final class CameraExtensionSettings: RealtimeCanvas {
    private let controller: CameraSessionController
    private let cameraExtension: CameraExtensionController
    private let heading = realtimeLabel("Virtual Camera", size: 15, weight: .medium)
    private let status = realtimeLabel(size: 12, color: RealtimePalette.secondary)
    private let refresh = RealtimeButton()
    private let install = RealtimeButton("Install & Enable")
    private let remove = RealtimeButton("Remove", style: .destructive)
    private let openSettings = RealtimeButton("Open System Settings")
    private let spinner = RealtimeSpinner()

    init(controller: CameraSessionController, cameraExtension: CameraExtensionController) {
        self.controller = controller
        self.cameraExtension = cameraExtension
        super.init()
        frame.size = NSSize(width: 376, height: 220)
        status.maximumNumberOfLines = 0
        status.lineBreakMode = .byWordWrapping
        status.cell?.wraps = true
        status.cell?.usesSingleLineMode = false
        status.cell?.isScrollable = false
        refresh.symbolName = "arrow.clockwise"
        refresh.iconSize = 14
        refresh.setAccessibilityLabel("Refresh Virtual Camera")
        refresh.onClick = { [weak self] in self?.cameraExtension.refresh() }
        install.onClick = { [weak self] in self?.cameraExtension.install() }
        remove.onClick = { [weak self] in self?.cameraExtension.uninstall() }
        openSettings.onClick = { [weak self] in self?.cameraExtension.openSettings() }
        [heading, status, refresh, install, remove, openSettings, spinner].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update() {
        status.stringValue = cameraExtension.status
        refresh.isEnabled = !cameraExtension.isRefreshing && (!cameraExtension.isBusy || cameraExtension.isAwaitingApproval)
        install.title = cameraExtension.isEnabled ? "Update" : cameraExtension.isAwaitingApproval ? "Awaiting Approval" : "Install & Enable"
        install.isEnabled = !controller.settingsLocked && !cameraExtension.isBusy && !cameraExtension.isRefreshing
        remove.isEnabled = install.isEnabled
        remove.isHidden = !cameraExtension.isEnabled
        let waiting = cameraExtension.isBusy && !cameraExtension.isAwaitingApproval
        spinner.isHidden = !waiting
        spinner.setSpinning(waiting, color: RealtimePalette.secondary)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        heading.frame = NSRect(x: 18, y: 23, width: 280, height: 24)
        refresh.frame = NSRect(x: bounds.width - 48, y: 18, width: 30, height: 30)
        var y: CGFloat = 64
        place(status, at: &y)
        install.frame = NSRect(x: 18, y: y, width: install.preferredWidth, height: 36)
        remove.frame = NSRect(x: install.frame.maxX + 10, y: y, width: remove.preferredWidth, height: 36)
        y += 52
        if !spinner.isHidden {
            spinner.frame = NSRect(x: 18, y: y, width: 16, height: 16)
            y += 32
        }
        openSettings.frame = NSRect(x: 18, y: y, width: openSettings.preferredWidth, height: 36)
        let height = y + 54
        if frame.height != height { setFrameSize(NSSize(width: frame.width, height: height)) }
    }

    private func place(_ label: NSTextField, at y: inout CGFloat) {
        let width = bounds.width - 36
        let height = ceil(label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height ?? 20)
        label.frame = NSRect(x: 18, y: y, width: width, height: height)
        y += height + 16
    }
}
