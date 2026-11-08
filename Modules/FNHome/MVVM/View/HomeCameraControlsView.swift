//
//  HomeCameraControlsView.swift
//  FaceNow
//

import AppKit
import SnapKit

/// Presents a neutral virtual-device entry and owns its transient status popover.
@MainActor
final class HomeCameraControlsView: Canvas {

    /// Opens the requested video-call guide stage.
    var onShowOnboarding: ((OnboardingRepository.Step?) -> Void)?

    /// Opens the camera-extension pane in System Settings.
    var onOpenCameraSettings: (() -> Void)?

    /// Opens the microphone module's existing explicit setup flow.
    var onShowMicrophoneSetup: (() -> Void)?

    /// Retains the currently presented native popover.
    private var popover: NSPopover?

    /// Preserves the shared toolbar surface without coloring it by device status.
    private lazy var devicesButton: ToolbarButton = {
        let view = ToolbarButton(
            content: .labeled(HomeStrings.virtualDevices, icon: .vector(.display)),
            role: .menu
        )
        view.onClick = { [weak self] in self?.togglePopover() }
        return view
    }()

    /// Keeps device rows updated while delegating navigation to the home coordinator.
    private lazy var devicesCard: HomeVirtualDevicesPopoverView = {
        let view = HomeVirtualDevicesPopoverView()
        view.onCameraSetup = { [weak self] in
            self?.closePopover()
            self?.onOpenCameraSettings?()
        }
        view.onMicrophoneSetup = { [weak self] in
            self?.closePopover()
            self?.onShowMicrophoneSetup?()
        }
        view.onShowGuide = { [weak self] in
            self?.closePopover()
            self?.onShowOnboarding?(.videoCalls)
        }
        return view
    }()

    /// Fits the status capsule to the shared header control area.
    init() {
        super.init()
        addSubview(devicesButton)
        devicesButton.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Measures the neutral device capsule using the shared toolbar metrics.
    var preferredWidth: CGFloat {
        devicesButton.preferredWidth
    }

    /// Dismisses device details during navigation, authentication changes, or shutdown.
    func closePopover() {
        popover?.close()
        popover = nil
    }

    /// Opens current device facts beneath the capsule without installing either device.
    private func togglePopover() {
        guard popover?.isShown != true else {
            closePopover()
            return
        }
        devicesCard.refresh()
        let controller = NSViewController()
        controller.view = devicesCard
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = controller
        popover.contentSize = devicesCard.fittingSize
        self.popover = popover
        popover.show(
            relativeTo: devicesButton.bounds,
            of: devicesButton,
            preferredEdge: .maxY
        )
    }
}
