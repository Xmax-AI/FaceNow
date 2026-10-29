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

/// Shares the Stop Session toolbar surface while reporting virtual-output availability.
@MainActor
final class VirtualCameraStatusView: Canvas {

    /// Caches only rendered state so repeated notifications do not restart appearance transitions.
    private var displayedState: CameraStatusViewModel.VirtualCameraIndicator?

    /// Uses the same fill, outline, shadow, typography metrics, and motion as Stop Session.
    private lazy var capsule: ToolbarButton = {
        let view = ToolbarButton(
            OnboardingStrings.virtualCamera,
            style: .destructive,
            weight: .semibold
        )
        view.passive = true
        view.alignment = .left
        view.trailingPadding = ToolbarControlMetrics.trailingPadding + 8 + 8
        view.setAccessibilityElement(false)
        return view
    }()

    /// The same semantic color identifies readiness in the trailing status light.
    private lazy var indicator: Canvas = {
        let view = Canvas(radius: 4)
        view.setAccessibilityElement(false)
        return view
    }()

    /// Composes a read-only toolbar capsule without introducing a separate surface recipe.
    init() {
        super.init()
        addSubview(capsule)
        capsule.addSubview(indicator)
        capsule.snp.makeConstraints { make in make.edges.equalToSuperview() }
        indicator.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(ToolbarControlMetrics.trailingPadding)
            make.centerY.equalToSuperview()
            make.size.equalTo(8)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(OnboardingStrings.virtualCamera)
        update(state: .checking)
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Preserves the capsule width through the shared toolbar control's own measurement.
    override var intrinsicContentSize: NSSize {
        NSSize(width: capsule.preferredWidth, height: 32)
    }

    /// Renders output readiness without installing, activating, or capturing a camera.
    func update(
        state: CameraStatusViewModel.VirtualCameraIndicator
    ) {
        guard displayedState != state else { return }
        displayedState = state
        let available = state == .available
        capsule.style = available ? .success : .destructive
        ControlMotion.set(
            (available ? Palette.success : Palette.destructive).cgColor,
            for: "backgroundColor",
            on: indicator.layer,
            in: self
        )
        toolTip = state.helpText
        capsule.toolTip = state.helpText
        setAccessibilityValue(state.helpText)
        if window != nil { NSAccessibility.post(element: self, notification: .valueChanged) }
    }
}
