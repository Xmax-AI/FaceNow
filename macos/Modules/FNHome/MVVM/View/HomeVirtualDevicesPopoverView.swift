//
//  HomeVirtualDevicesPopoverView.swift
//  FaceNow
//

import AppKit
import Combine
import SnapKit

/// Presents camera and microphone status with explicit setup and integration-guide actions.
@MainActor
final class HomeVirtualDevicesPopoverView: Canvas {

    /// Requests the camera-extension pane in System Settings.
    var onCameraSetup: (() -> Void)?

    /// Requests the microphone module's setup dialog.
    var onMicrophoneSetup: (() -> Void)?

    /// Requests the existing meeting-app integration guide.
    var onShowGuide: (() -> Void)?

    /// Derives presentation from shared device owners.
    private let viewModel = HomeVirtualDevicesViewModel()

    /// Retains device observation for the lifetime of the card.
    private var observation: AnyCancellable?

    /// Names the device group shown by the toolbar capsule.
    private lazy var heading: NSTextField = {
        let view = makeLabel(
            HomeStrings.virtualDevices,
            size: 18,
            color: Palette.softText,
            weight: .semibold
        )
        return view
    }()

    /// Shows actual virtual-output preparation independently of camera capture.
    private lazy var cameraRow: VirtualDeviceRowView = {
        let view = VirtualDeviceRowView(
            title: OnboardingStrings.virtualCamera,
            symbol: "video"
        )
        view.onSetup = { [weak self] in self?.onCameraSetup?() }
        return view
    }()

    /// Exposes the explicit audio setup flow, including when the driver is already available.
    private lazy var microphoneRow: VirtualDeviceRowView = {
        let view = VirtualDeviceRowView(
            title: VirtualMicrophoneStrings.title,
            symbol: "mic"
        )
        view.onSetup = { [weak self] in self?.onMicrophoneSetup?() }
        return view
    }()

    /// Separates device preparation from meeting-app instructions.
    private lazy var separator: Canvas = {
        let view = Canvas(color: Palette.border)
        return view
    }()

    /// Opens the guide only after an explicit click.
    private lazy var guideButton: Button = {
        let view = Button(HomeStrings.deviceGuide, style: .plain)
        view.font = Typography.font(size: 14, weight: .semibold)
        view.foregroundColor = Palette.accent
        view.onClick = { [weak self] in self?.onShowGuide?() }
        return view
    }()

    /// Composes a compact native card using stable constraints and live repository projections.
    init() {
        super.init(color: .white)
        [heading, cameraRow, microphoneRow, separator, guideButton].forEach(addSubview)
        snp.makeConstraints { make in
            make.width.equalTo(400)
        }
        heading.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(20)
            make.trailing.lessThanOrEqualToSuperview().inset(20)
        }
        cameraRow.snp.makeConstraints { make in
            make.top.equalTo(heading.snp.bottom).offset(18)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(48)
        }
        microphoneRow.snp.makeConstraints { make in
            make.top.equalTo(cameraRow.snp.bottom).offset(10)
            make.leading.trailing.height.equalTo(cameraRow)
        }
        separator.snp.makeConstraints { make in
            make.top.equalTo(microphoneRow.snp.bottom).offset(18)
            make.leading.trailing.equalTo(cameraRow)
            make.height.equalTo(1)
        }
        guideButton.snp.makeConstraints { make in
            make.top.equalTo(separator.snp.bottom).offset(10)
            make.leading.trailing.equalTo(cameraRow)
            make.height.equalTo(32)
            make.bottom.equalToSuperview().inset(12)
        }
        cameraRow.alignStatusColumn(with: microphoneRow)
        observation = viewModel.changes.sink { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.update() }
        }
        update()
    }

    /// Storyboard decoding is unsupported for this programmatic card.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Shows cached facts immediately while a silent device refresh is pending.
    func refresh() {
        update()
        viewModel.refresh()
    }

    /// Renders repository state without changing the neutral toolbar capsule.
    private func update() {
        cameraRow.update(
            status: viewModel.cameraStatus,
            showsSetup: true
        )
        microphoneRow.update(
            status: viewModel.microphoneStatus,
            showsSetup: true
        )
    }
}

/// Aligns one device name, status dot, and optional setup link inside a neutral row.
@MainActor
private final class VirtualDeviceRowView: Canvas {

    /// Requests setup without performing system operations in the view.
    var onSetup: (() -> Void)?

    /// The localized device name used by its label and accessibility element.
    private let title: String

    /// The system symbol identifying the device capability.
    private let symbol: String

    /// Identifies the device with a monochrome outline glyph.
    private lazy var iconView: NSImageView = {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        view.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        view.contentTintColor = Palette.secondary
        return view
    }()

    /// Keeps the device name at its natural text width.
    private lazy var titleLabel: NSTextField = {
        let view = makeLabel(
            title,
            size: 13,
            color: Palette.softText,
            weight: .semibold
        )
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        return view
    }()

    /// Supplements the written status without relying on color alone.
    private lazy var statusDot: Canvas = {
        let view = Canvas(radius: 4)
        view.setAccessibilityElement(false)
        return view
    }()

    /// Displays readiness without claiming that a generated media stream is active.
    private lazy var statusLabel: NSTextField = {
        let view = makeLabel(size: 13, color: Palette.secondary)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        return view
    }()

    /// Keeps the status dot and its written explanation together.
    private lazy var statusGroup: NSStackView = {
        let view = NSStackView(views: [statusDot, statusLabel])
        view.orientation = .horizontal
        view.alignment = .centerY
        view.spacing = 6
        return view
    }()

    /// Routes setup through the parent card while keeping native button motion.
    private lazy var setupButton: Button = {
        let view = Button(HomeStrings.deviceSetup, style: .plain)
        view.font = Typography.font(size: 13, weight: .semibold)
        view.foregroundColor = Palette.accent
        view.leadingPadding = 0
        view.trailingPadding = 0
        view.setAccessibilityLabel(title + ", " + HomeStrings.deviceSetup)
        view.onClick = { [weak self] in self?.onSetup?() }
        return view
    }()

    /// Holds the right-aligned status and setup action at their intrinsic sizes.
    private lazy var trailingGroup: NSStackView = {
        let view = NSStackView(views: [statusGroup, setupButton])
        view.orientation = .horizontal
        view.alignment = .centerY
        view.spacing = 14
        view.detachesHiddenViews = false
        return view
    }()

    /// Composes a fixed-height row with intrinsic text and a flexible middle gap.
    init(
        title: String,
        symbol: String
    ) {
        self.title = title
        self.symbol = symbol
        super.init(color: Palette.surface, radius: 12)
        [iconView, titleLabel, trailingGroup].forEach(addSubview)
        iconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(12)
            make.centerY.equalToSuperview()
            make.size.equalTo(22)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconView.snp.trailing).offset(10)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualTo(trailingGroup.snp.leading).offset(-12)
        }
        trailingGroup.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(12)
            make.centerY.equalToSuperview()
        }
        statusDot.snp.makeConstraints { make in
            make.size.equalTo(8)
        }
        setupButton.snp.makeConstraints { make in
            make.width.equalTo(setupButton.preferredWidth)
            make.height.equalTo(28)
        }
    }

    /// Storyboard decoding is unsupported for this programmatic row.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Keeps status dots aligned even when only one row needs a setup link.
    func alignStatusColumn(
        with row: VirtualDeviceRowView
    ) {
        statusGroup.snp.makeConstraints { make in
            make.width.equalTo(row.statusGroup)
        }
    }

    /// Updates the written status, semantic color, and relevant setup affordance.
    func update(
        status: HomeVirtualDevicesViewModel.Status,
        showsSetup: Bool
    ) {
        statusLabel.stringValue = status.title
        let color: NSColor =
            switch status {
            case .enabled: .systemGreen
            case .checking: Palette.secondary
            case .failed, .disabled: .systemRed
            case .notInstalled, .needsSetup, .pending: .systemOrange
            }
        statusDot.layer?.backgroundColor = color.cgColor
        setupButton.isHidden = !showsSetup
    }
}
