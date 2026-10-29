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

/// Keeps setup help and virtual-output availability in the home header.
@MainActor
final class HomeCameraControlsView: Canvas {

    /// Opens the preparation flow at its first incomplete stage.
    var onShowOnboarding: ((OnboardingRepository.Step?) -> Void)?

    /// Reopens the preparation guide immediately to the left of virtual-camera status.
    private lazy var guideButton: ToolbarButton = {
        let view = ToolbarButton(shape: .circle)
        view.symbolName = "info.circle"
        view.toolTip = HomeStrings.homeHowToUseFaceNowInVideoCalls
        view.setAccessibilityLabel(HomeStrings.homeOpenFaceNowSetupGuide)
        view.onClick = { [weak self] in self?.onShowOnboarding?(nil) }
        return view
    }()

    /// Occupies the former physical-camera selector position in the header.
    private lazy var virtualCameraStatus: VirtualCameraStatusView = {
        let view = VirtualCameraStatusView()
        return view
    }()

    /// Composes the guide and status capsule using the common header height and spacing.
    init() {
        super.init()
        [guideButton, virtualCameraStatus].forEach(addSubview)
        guideButton.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
        }
        virtualCameraStatus.snp.makeConstraints { make in
            make.leading.equalTo(guideButton.snp.trailing).offset(ToolbarControlMetrics.spacing)
            make.top.bottom.trailing.equalToSuperview()
            make.width.equalTo(virtualCameraStatus.intrinsicContentSize.width)
        }
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Includes the guide's circular diameter and the full status-capsule width.
    func preferredWidth(
        controlHeight: CGFloat
    ) -> CGFloat {
        guideButton.preferredWidth(controlHeight: controlHeight)
            + ToolbarControlMetrics.spacing + virtualCameraStatus.intrinsicContentSize.width
    }

    /// Renders the same output state used by home notices and setup guidance.
    func update(
        state: CameraStatusViewModel.VirtualCameraIndicator
    ) {
        virtualCameraStatus.update(state: state)
    }
}
