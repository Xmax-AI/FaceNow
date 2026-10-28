//
//  OnboardingSetupView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Factory
import AppKit
import SnapKit

/// Persistent extension installation controls, updated independently of the session page.
@MainActor
final class OnboardingSetupView: Canvas {

    /// Invokes the host-owned diagnostic video action.
    var onTestVideo: (() -> Void)?

    /// The extension owner supplying installation actions and readiness state.
    @Injected(\.virtualCameraRepo) private var virtualCameraRepo: VirtualCameraRepository

    /// The setup labels and availability derived without owning native controls.
    private lazy var viewModel: OnboardingSetupViewModel = {
        let viewModel = OnboardingSetupViewModel()
        return viewModel
    }()

    /// The virtual-camera setup title.
    private lazy var heading: NSTextField = {
        let view = makeLabel(
            "Virtual Camera",
            size: 15,
            weight: .medium
        )
        return view
    }()

    /// The wrapping system or device-readiness status message.
    private lazy var status: NSTextField = {
        let view = makeLabel(
            size: 12,
            color: Palette.secondary
        )
        view.maximumNumberOfLines = 0
        view.lineBreakMode = .byWordWrapping
        view.cell?.wraps = true
        view.cell?.usesSingleLineMode = false
        view.cell?.isScrollable = false
        return view
    }()

    /// Requests an explicit extension and device-readiness refresh.
    private lazy var refresh: Button = {
        let view = Button()
        view.symbolName = "arrow.clockwise"
        view.iconSize = 14
        view.setAccessibilityLabel("Refresh Virtual Camera")
        view.toolTip = "Refresh camera extension status"
        view.onClick = { [weak self] in self?.virtualCameraRepo.refresh(retryDeviceDiscovery: true) }
        return view
    }()

    /// Requests installation or replacement of the bundled camera extension.
    private lazy var install: Button = {
        let view = Button("Install & Enable")
        view.onClick = { [weak self] in self?.virtualCameraRepo.install() }
        return view
    }()

    /// Requests removal of the currently installed extension.
    private lazy var remove: Button = {
        let view = Button(
            "Remove",
            style: .destructive
        )
        view.onClick = { [weak self] in self?.virtualCameraRepo.uninstall() }
        return view
    }()

    /// Opens the system's extension settings after a user action.
    private lazy var openSettings: Button = {
        let view = Button("Open System Settings")
        view.onClick = { [weak self] in self?.virtualCameraRepo.openSettings() }
        return view
    }()

    /// Invokes the optional diagnostic video action owned by the home coordinator.
    private lazy var testVideo: Button = {
        let view = Button("Test Video")
        view.onClick = { [weak self] in
            self?.onTestVideo?()
        }
        return view
    }()

    /// Indicates pending system queries, activation, or device publication.
    private lazy var spinner: Spinner = {
        let view = Spinner()
        return view
    }()

    /// Creates setup actions without owning generation or initiating installation.
    init() {
        super.init()
        [heading, status, refresh, install, remove, openSettings, testVideo, spinner].forEach(addSubview)
        configureLayout()
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Applies current session restrictions without owning the generation session.
    func update(
        settingsLocked: Bool,
        testPatternActive: Bool,
        isBusy: Bool,
        sessionActive: Bool
    ) {
        status.stringValue = viewModel.status
        refresh.isEnabled = viewModel.canRefresh
        install.title = viewModel.installTitle
        install.isEnabled = viewModel.canInstall(settingsLocked: settingsLocked)
        remove.isEnabled = install.isEnabled
        remove.isHidden = !viewModel.showsRemove
        testVideo.isHidden = !viewModel.showsTestVideo
        testVideo.title = testPatternActive ? "Stop Test Video" : "Test Video"
        testVideo.isEnabled = viewModel.canTestVideo(
            isBusy: isBusy,
            sessionActive: sessionActive
        )
        let waiting = viewModel.isWaiting
        refresh.isHidden = waiting
        spinner.isHidden = !waiting
        spinner.setSpinning(
            waiting,
            color: Palette.secondary
        )
        updateActionConstraints()
        invalidateIntrinsicContentSize()
    }

    /// The currently available setup and optional diagnostic controls.
    private var actionButtons: [Button] {
        let setup = remove.isHidden ? [install, openSettings] : [install, remove, openSettings]
        return testVideo.isHidden ? setup : setup + [testVideo]
    }

    /// Measures the popover boundary from content while child positions remain constrained.
    override var intrinsicContentSize: NSSize {
        let buttons = actionButtons
        let width = max(376, buttons.reduce(CGFloat(36)) { $0 + $1.preferredWidth } + CGFloat(buttons.count - 1) * 10)
        let textHeight = ceil(
            status.cell?.cellSize(
                forBounds: NSRect(
                    x: 0,
                    y: 0,
                    width: width - 36,
                    height: .greatestFiniteMagnitude
                )
            ).height ?? 20
        )
        return NSSize(width: width, height: 134 + textHeight)
    }

    /// Tracks the visible action identities and status measurement without rebuilding unchanged rows.
    private var actionSignature = ""

    /// Installs the header and wrapping status above the action row.
    private func configureLayout() {
        heading.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(18)
            make.top.equalToSuperview().offset(23)
            make.trailing.lessThanOrEqualTo(refresh.snp.leading).offset(-18)
            make.height.equalTo(24)
        }
        refresh.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(18)
            make.top.equalToSuperview().offset(18)
            make.size.equalTo(30)
        }
        spinner.snp.makeConstraints { make in
            make.center.equalTo(refresh)
            make.size.equalTo(16)
        }
        status.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(18)
            make.top.equalToSuperview().offset(64)
            make.height.equalTo(20)
        }
        updateActionConstraints()
    }

    /// Reflows only when wrapping status text or the visible actions actually change.
    private func updateActionConstraints() {
        let buttons = actionButtons
        let signature = status.stringValue + buttons.map { "\($0.title):\($0.preferredWidth)" }.joined(separator: "|")
        guard signature != actionSignature else { return }
        actionSignature = signature
        status.snp.updateConstraints { make in make.height.equalTo(intrinsicContentSize.height - 134) }
        for button in [install, remove, openSettings, testVideo] { button.snp.removeConstraints() }
        var previous: Button?
        for button in buttons {
            button.snp.makeConstraints { make in
                make.top.equalTo(status.snp.bottom).offset(16)
                make.height.equalTo(36)
                make.width.equalTo(button.preferredWidth)
                if let previous {
                    make.leading.equalTo(previous.snp.trailing).offset(10)
                } else {
                    make.leading.equalToSuperview().offset(18)
                }
            }
            previous = button
        }
    }
}
