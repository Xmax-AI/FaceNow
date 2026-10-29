//
//  HomeCameraControlsView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import SnapKit

/// Presents virtual-output availability and its onboarding entry in the home header.
@MainActor
final class HomeCameraControlsView: Canvas {

    /// Opens the preparation flow at the requested stage.
    var onShowOnboarding: ((OnboardingRepository.Step?) -> Void)?

    /// Occupies the former physical-camera selector position in the header.
    private lazy var virtualCameraStatus: VirtualCameraStatusView = {
        let view = VirtualCameraStatusView()
        view.onShowOnboarding = { [weak self] in self?.onShowOnboarding?(.virtualCamera) }
        return view
    }()

    /// Fits the status capsule to the shared header control area.
    init() {
        super.init()
        addSubview(virtualCameraStatus)
        virtualCameraStatus.snp.makeConstraints { make in make.edges.equalToSuperview() }
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Measures the status capsule without reserving a separate help-button slot.
    var preferredWidth: CGFloat { virtualCameraStatus.intrinsicContentSize.width }

    /// Renders the same output state used by home notices and setup guidance.
    func update(
        state: CameraStatusViewModel.VirtualCameraIndicator
    ) {
        virtualCameraStatus.update(state: state)
    }
}
