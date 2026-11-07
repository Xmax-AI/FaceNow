//
//  VirtualCameraStatusView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import SnapKit

/// Reports virtual-output availability and opens its guide through a shared toolbar button.
@MainActor
final class VirtualCameraStatusView: Canvas {

    /// Requests presentation of the virtual-camera onboarding step.
    var onShowOnboarding: (() -> Void)?

    /// Caches only rendered state so repeated notifications do not restart appearance transitions.
    private var displayedState: CameraStatusViewModel.VirtualCameraIndicator?

    /// Uses the same fill, outline, shadow, typography metrics, and motion as Stop Session.
    private lazy var capsule: Button = {
        let view = Button(
            OnboardingStrings.virtualCamera,
            style: .destructive
        )
        view.chevron = true
        view.configureForToolbar(weight: .semibold)
        view.usesStatusAppearance = true
        view.leadingPadding = 16
        view.chevronTrailingPadding = 14
        view.trailingPadding = view.chevronTrailingPadding + ToolbarControlMetrics.disclosureWidth + 6
        view.setAccessibilityLabel(OnboardingStrings.virtualCamera)
        view.onClick = { [weak self] in self?.onShowOnboarding?() }
        return view
    }()

    /// Composes an actionable capsule with more leading space and a compact disclosure area.
    init() {
        super.init()
        addSubview(capsule)
        capsule.snp.makeConstraints { make in make.edges.equalToSuperview() }
        setAccessibilityElement(false)
        update(state: .checking)
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Preserves the capsule width through the shared toolbar control's own measurement.
    override var intrinsicContentSize: NSSize {
        NSSize(width: capsule.preferredWidth, height: ToolbarControlMetrics.compactHeight)
    }

    /// Renders output readiness without installing, activating, or capturing a camera.
    func update(
        state: CameraStatusViewModel.VirtualCameraIndicator
    ) {
        guard displayedState != state else { return }
        displayedState = state
        let available = state == .available
        capsule.style = available ? .success : .destructive
        toolTip = state.helpText
        capsule.toolTip = state.helpText
        capsule.setAccessibilityValue(state.helpText)
        if window != nil { NSAccessibility.post(element: capsule, notification: .valueChanged) }
    }
}
