//
//  OnboardingGuideView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import SnapKit

/// Presents an accessible, dismissible preparation dialog over the mounted home page.
@MainActor
final class OnboardingGuideView: Canvas {

    /// Executes the primary action selected for the current stage.
    var onPrimary: (() -> Void)?

    /// Leaves preparation unfinished and returns to the home page.
    var onDismiss: (() -> Void)?

    /// Controls only backdrop clicks; explicit dismissal and Escape keep their existing behavior.
    var dismissesOnBackdropClick = true

    /// Returns to the preceding device stage.
    var onPrevious: (() -> Void)?

    /// Selects the shared physical input without starting capture.
    var onSelectCamera: ((String) -> Void)?

    /// The app selected for the repeatable video-call instructions.
    private var selectedApp = "WeChat"

    /// The visible stage used to update the video-call illustration after app selection.
    private var displayedStep = OnboardingRepository.Step.camera

    /// The device-list identity used to preserve the native popup while values are unchanged.
    private var cameraSignature = ""

    /// Blocks child interaction while the modal is leaving the home page.
    private var isDismissing = false

    /// Prevents changing body content from influencing the modal's viewport-derived width.
    private var cardWidth: CGFloat = 980

    /// The independent dimming layer whose opacity does not affect the modal card.
    private lazy var backdrop: Canvas = {
        let view = Canvas(color: NSColor.black.withAlphaComponent(0.35))
        view.setAccessibilityElement(false)
        view.addGestureRecognizer(
            NSClickGestureRecognizer(
                target: self,
                action: #selector(dismissFromBackdrop)
            )
        )
        return view
    }()

    /// The white modal surface, sized relative to the host window.
    private lazy var card: Canvas = {
        let view = Canvas(color: .white, radius: 22)
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowOpacity = 0.16
        view.layer?.shadowRadius = 28
        view.layer?.shadowOffset = CGSize(width: 0, height: -8)
        view.setAccessibilityRole(.group)
        view.setAccessibilityModal(true)
        view.setAccessibilityLabel(OnboardingStrings.guideGetReadyToUseFaceNow)
        return view
    }()

    /// The fixed dialog title above the progress indicators.
    private lazy var heading: NSTextField = {
        let view = makeLabel(OnboardingStrings.guideGetReadyForUse, size: 26, weight: .semibold)
        return view
    }()

    /// The explicit dismissal control, also reachable with Escape.
    private lazy var closeButton: Button = {
        let view = Button(style: .plain)
        view.symbolName = "xmark"
        view.centersSymbolVisually = true
        view.iconSize = 16
        view.foregroundColor = Palette.secondary
        view.hoverBackgroundColor = Palette.surface
        view.cornerRadius = 8
        view.showsShadow = false
        view.setAccessibilityLabel(OnboardingStrings.guideCloseSetupGuide)
        view.keyEquivalent = "\u{1b}"
        view.keyEquivalentModifierMask = []
        view.onClick = { [weak self] in self?.onDismiss?() }
        return view
    }()

    /// The connected preparation steps with numbered, active, and completed badges.
    private lazy var progress: OnboardingProgressView = {
        let view = OnboardingProgressView()
        return view
    }()

    /// The scroll boundary keeps the body usable on short displays.
    private lazy var scroll: NSScrollView = {
        let view = NSScrollView()
        view.drawsBackground = false
        view.hasVerticalScroller = true
        view.scrollerStyle = .overlay
        return view
    }()

    /// The two-column body, with a minimum height independent of window sizing.
    private lazy var body: Canvas = {
        let view = Canvas()
        return view
    }()

    /// The vertically arranged explanation and device controls.
    private lazy var copy: NSStackView = {
        let view = NSStackView()
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 16
        return view
    }()

    /// The stage-specific headline.
    private lazy var title: NSTextField = {
        let view = wrappingLabel(size: 26, weight: .semibold)
        return view
    }()

    /// Explains why the current preparation step is needed.
    private lazy var subtitle: NSTextField = {
        let view = wrappingLabel(size: 14, color: Palette.secondary)
        return view
    }()

    /// The ordered setup instructions with numbered milestones, headings, and supporting copy.
    private lazy var timeline: OnboardingTimelineView = {
        let view = OnboardingTimelineView()
        return view
    }()

    /// The meeting app whose camera-selection guidance is displayed.
    private lazy var appPicker: NSPopUpButton = {
        let view = NSPopUpButton()
        view.addItems(withTitles: ["WeChat", "Feishu", "Tencent Meeting", "Zoom", "Google Meet"])
        view.font = Typography.font(size: 13)
        view.menu?.items.forEach {
            $0.attributedTitle = NSAttributedString(
                string: $0.title,
                attributes: [.font: Typography.font(size: 13)]
            )
        }
        view.target = self
        view.action = #selector(selectApp)
        view.setAccessibilityLabel(OnboardingStrings.guideVideoCallingApp)
        return view
    }()

    /// The physical input choices populated only after shared discovery is available.
    private lazy var cameraPicker: NSPopUpButton = {
        let view = NSPopUpButton()
        view.font = Typography.font(size: 13)
        view.target = self
        view.action = #selector(selectCamera)
        view.setAccessibilityLabel(OnboardingStrings.guideInputCamera)
        return view
    }()

    /// The illustrative panel highlighting the settings action or camera-menu selection.
    private lazy var illustration: OnboardingIllustrationView = {
        let view = OnboardingIllustrationView()
        return view
    }()

    /// The footer boundary separates navigation from the setup content.
    private lazy var divider: Canvas = {
        let view = Canvas(color: Palette.border)
        return view
    }()

    /// Revisits a completed device requirement.
    private lazy var previous: Button = {
        let view = Button(OnboardingStrings.back, style: .plain)
        view.font = Typography.font(size: 13)
        view.alignment = .left
        view.onClick = { [weak self] in self?.onPrevious?() }
        return view
    }()

    /// Defers preparation while retaining the persistent home reminder.
    private lazy var later: Button = {
        let view = Button(OnboardingStrings.guideSetUpLater, style: .plain)
        view.font = Typography.font(size: 13)
        view.alignment = .left
        view.onClick = { [weak self] in self?.onDismiss?() }
        return view
    }()

    /// Left-aligns footer actions and removes the space occupied by hidden navigation buttons.
    private lazy var footerNavigation: NSStackView = {
        let view = NSStackView(views: [previous, later])
        view.orientation = .horizontal
        view.alignment = .centerY
        view.spacing = 24
        view.detachesHiddenViews = true
        return view
    }()

    /// Runs the explicit permission, installation, or completion action.
    private lazy var primary: Button = {
        let view = Button(style: .primary)
        view.font = Typography.font(size: 14, weight: .semibold)
        view.cornerRadius = 12
        view.shadowScale = 0.6
        view.leadingPadding = 24
        view.trailingPadding = 24
        view.onClick = { [weak self] in self?.onPrimary?() }
        return view
    }()

    /// Composes a modal overlay while retaining the underlying home and preview bindings.
    init() {
        super.init()
        addSubview(backdrop)
        addSubview(card)
        [heading, closeButton, progress, scroll, divider, footerNavigation, primary].forEach(card.addSubview)
        scroll.documentView = body
        [copy, illustration].forEach(body.addSubview)
        [title, subtitle, appPicker, timeline, cameraPicker].forEach {
            copy.addArrangedSubview($0)
            $0.snp.makeConstraints { make in make.width.equalTo(copy) }
        }
        copy.setCustomSpacing(24, after: subtitle)
        configureLayout()
        backdrop.layer?.opacity = 0
        card.layer?.opacity = 0
    }

    /// Storyboard decoding is unsupported for this programmatic view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Prevents keyboard events from reaching the covered home page.
    override var acceptsFirstResponder: Bool { true }

    /// Dismisses preparation without saving completion when Escape is pressed.
    override func cancelOperation(
        _ sender: Any?
    ) { onDismiss?() }

    /// Focuses the first modal action after the guide is attached to a window.
    func focus() { window?.makeFirstResponder(closeButton) }

    /// Sizes the modal from its host viewport instead of permission-dependent intrinsic content.
    override func layout() {
        let width = min(980, max(0, bounds.width - 64))
        if bounds.width > 0, cardWidth != width {
            cardWidth = width
            card.snp.updateConstraints { make in make.width.equalTo(width) }
        }
        super.layout()
    }

    /// Routes backdrop dismissal through the same animated exit as the explicit close action.
    @objc private func dismissFromBackdrop() {
        guard dismissesOnBackdropClick, !isDismissing else { return }
        onDismiss?()
    }

    /// Keeps closing gestures from reaching either the modal controls or the covered home page.
    override func hitTest(
        _ point: NSPoint
    ) -> NSView? {
        if isDismissing {
            return bounds.contains(convert(point, from: superview)) ? self : nil
        }
        return super.hitTest(point)
    }

    /// Fades the backdrop and card independently while the card decelerates into its centered position.
    func animatePresentation(
        visible: Bool
    ) {
        isDismissing = !visible
        if isDismissing { window?.makeFirstResponder(self) }
        ControlMotion.set(
            Float(visible ? 1 : 0),
            for: "opacity",
            on: backdrop.layer,
            in: self
        )
        ControlMotion.set(
            Float(visible ? 1 : 0),
            for: "opacity",
            on: card.layer,
            in: self
        )
        // Resolve the initial lower position before animating AppKit-owned view geometry.
        layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ControlMotion.isAnimated(in: self) ? ControlMotion.duration : 0
            context.timingFunction =
                visible
                ? CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
                : CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            card.snp.updateConstraints { make in
                make.centerY.equalToSuperview().offset(visible ? 0 : 24)
            }
            layoutSubtreeIfNeeded()
        }
    }

    /// Reflects committed preparation state without rebuilding controls or their focus.
    func update(
        model: OnboardingFlowViewModel
    ) {
        let repo = model.onboardingRepo
        displayedStep = repo.step
        progress.update(
            current: repo.step,
            cameraReady: repo.cameraReady,
            virtualCameraReady: repo.virtualCameraReady
        )
        appPicker.isHidden = repo.step != .videoCalls
        cameraPicker.isHidden = repo.step != .camera || model.generationRepo.cameras.isEmpty
        cameraPicker.isEnabled = !model.generationRepo.settingsLocked
        previous.isHidden = repo.step == .camera
        later.isHidden = repo.step == .videoCalls
        primary.title = model.primaryTitle
        primary.isEnabled = model.primaryEnabled
        primary.loading = model.primaryLoading
        primary.snp.updateConstraints { make in make.width.equalTo(primary.preferredWidth) }
        switch repo.step {
        case .camera:
            title.stringValue = model.cameraStepTitle
            subtitle.stringValue = model.cameraStepDescription
            timeline.update(items: model.preparationInstructions.map { .init(title: $0.title, detail: $0.detail) })
        case .virtualCamera:
            title.stringValue = OnboardingStrings.guideEnableVirtualCamera
            subtitle.stringValue = OnboardingStrings.guideFaceNowUsesAVirtualCameraToBringYourChosen
            timeline.update(items: model.preparationInstructions.map { .init(title: $0.title, detail: $0.detail) })
        case .videoCalls:
            title.stringValue = OnboardingStrings.guideUseFaceNowInVideoCalls
            subtitle.stringValue = OnboardingStrings.guideChooseFaceNowAsYourCameraInYourVideoCalling
            updateCallInstructions()
        }
        updateCameras(model: model)
        let instruction = model.preparationInstructions.first
        illustration.update(
            step: repo.step,
            app: selectedApp,
            preparationTitle: instruction?.title ?? model.primaryTitle,
            primaryTitle: model.primaryTitle,
            preparationDetail: instruction?.detail ?? ""
        )
        let controls: [NSControl] =
            ([closeButton, appPicker, cameraPicker]
            + illustration.navigationControls + [previous, later, primary])
            .filter { !$0.isHidden && $0.isEnabled }
        for (index, control) in controls.enumerated() {
            control.nextKeyView = controls[(index + 1) % controls.count]
        }
    }

    /// Installs responsive dialog relationships with a separately scrollable body.
    private func configureLayout() {
        backdrop.snp.makeConstraints { make in make.edges.equalToSuperview() }
        card.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(24)
            // A constant updated from the viewport cannot impose a minimum width on the host window.
            make.width.equalTo(cardWidth)
            make.height.equalToSuperview().offset(-64).priority(490)
            make.height.lessThanOrEqualTo(640)
        }
        heading.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(28)
        }
        closeButton.snp.makeConstraints { make in
            make.trailing.top.equalToSuperview().inset(22)
            make.size.equalTo(32)
        }
        progress.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(28)
            make.trailing.lessThanOrEqualToSuperview().inset(28)
            make.width.equalToSuperview().offset(-96).priority(490)
            make.width.lessThanOrEqualTo(820)
            make.top.equalTo(heading.snp.bottom).offset(32)
            make.height.equalTo(30)
        }
        divider.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalToSuperview().inset(82)
            make.height.equalTo(1)
        }
        scroll.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(28)
            make.top.equalTo(progress.snp.bottom).offset(32)
            make.bottom.equalTo(divider.snp.top).offset(-20)
        }
        body.snp.makeConstraints { make in
            make.leading.top.equalTo(scroll.contentView)
            make.width.equalTo(scroll.contentView)
            make.height.equalTo(scroll.contentView).priority(490)
            make.height.greaterThanOrEqualTo(370)
        }
        copy.snp.makeConstraints { make in
            make.leading.top.equalToSuperview()
            make.width.equalTo(illustration)
            make.bottom.lessThanOrEqualToSuperview()
        }
        illustration.snp.makeConstraints { make in
            make.leading.equalTo(copy.snp.trailing).offset(28)
            make.trailing.top.bottom.equalToSuperview()
        }
        [cameraPicker, appPicker].forEach { view in
            view.snp.makeConstraints { make in make.height.equalTo(32) }
        }
        footerNavigation.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(28)
            make.centerY.equalTo(primary)
            make.trailing.lessThanOrEqualTo(primary.snp.leading).offset(-24)
        }
        previous.snp.makeConstraints { make in
            make.size.equalTo(CGSize(width: 48, height: 32))
        }
        later.snp.makeConstraints { make in
            make.size.equalTo(CGSize(width: 100, height: 32))
        }
        primary.snp.makeConstraints { make in
            make.trailing.bottom.equalToSuperview().inset(24)
            make.height.equalTo(42)
            make.width.equalTo(primary.preferredWidth)
        }
    }

    /// Updates the native input menu only when discovered identities or selection change.
    private func updateCameras(
        model: OnboardingFlowViewModel
    ) {
        let cameras = model.generationRepo.cameras
        let signature = cameras.map { $0.id + $0.name }.joined() + model.generationRepo.cameraID
        guard signature != cameraSignature else { return }
        cameraSignature = signature
        cameraPicker.removeAllItems()
        for camera in cameras {
            cameraPicker.addItem(withTitle: camera.name)
            cameraPicker.lastItem?.representedObject = camera.id
            cameraPicker.lastItem?.attributedTitle = NSAttributedString(
                string: camera.name,
                attributes: [.font: Typography.font(size: 13)]
            )
            if camera.id == model.generationRepo.cameraID { cameraPicker.select(cameraPicker.lastItem) }
        }
    }

    /// Presents the input picker inside the guide rather than beneath its modal backdrop.
    func showCameraPicker() {
        guard !cameraPicker.isHidden, cameraPicker.isEnabled, cameraPicker.numberOfItems > 0 else { return }
        window?.makeFirstResponder(cameraPicker)
        cameraPicker.performClick(nil)
    }

    /// Commits a native camera selection through the shared session owner.
    @objc private func selectCamera() {
        if let id = cameraPicker.selectedItem?.representedObject as? String { onSelectCamera?(id) }
    }

    /// Switches the repeatable instructions without changing any meeting-app settings.
    @objc private func selectApp() {
        selectedApp = appPicker.titleOfSelectedItem ?? "WeChat"
        updateCallInstructions()
        illustration.updateVideoCallApp(selectedApp)
    }

    /// Highlights the camera-menu entry and uses the real published device name.
    private func updateCallInstructions() {
        let first =
            selectedApp == "Google Meet"
            ? OnboardingStrings.guideOpenSettingsVideoInGoogleMeet
            : OnboardingStrings.openVideoSettings(app: selectedApp)
        timeline.update(items: [
            .init(title: OnboardingStrings.guideOpenVideoSettings, detail: first),
            .init(
                title: OnboardingStrings.guideSelectFaceNowCamera,
                detail: OnboardingStrings.chooseCameraNamed(name: VirtualCameraConfiguration.deviceName)
            ),
            .init(
                title: OnboardingStrings.guideStartYourCamera,
                detail: OnboardingStrings.guideReturnToFaceNowClickStartCameraAndChooseYour
            ),
        ])
    }
}

/// Presents numbered setup milestones with connecting rules, action headings, and descriptions.
@MainActor
private final class OnboardingTimelineView: Canvas {

    /// The heading and supporting instruction for one ordered action.
    struct Item: Equatable {

        /// The concise action heading.
        let title: String

        /// The explanatory copy below the heading.
        let detail: String
    }

    /// The last rendered instructions, used to preserve rows during ordinary state refreshes.
    private var items: [Item] = []

    /// Rebuilds decorative rows only when the selected guide or meeting-app instructions change.
    func update(
        items: [Item]
    ) {
        guard self.items != items else { return }
        self.items = items
        subviews.forEach { $0.removeFromSuperview() }
        var previous: Canvas?
        var badges: [Canvas] = []
        for (index, item) in items.enumerated() {
            let row = Canvas()
            let badge = Canvas(color: Palette.surface, radius: 16)
            badge.layer?.borderWidth = 1
            badge.layer?.borderColor = Palette.border.cgColor
            let number = makeLabel(String(index + 1), size: 14, weight: .medium)
            number.alignment = .center
            badge.addSubview(number)
            let title = wrappingLabel(size: 17, weight: .semibold)
            title.stringValue = item.title
            let detail = wrappingLabel(size: 14, color: Palette.secondary)
            detail.stringValue = item.detail
            [badge, title, detail].forEach(row.addSubview)
            addSubview(row)
            row.snp.makeConstraints { make in
                make.leading.trailing.equalToSuperview()
                make.height.greaterThanOrEqualTo(32)
                if let previous {
                    make.top.equalTo(previous.snp.bottom).offset(36)
                } else {
                    make.top.equalToSuperview()
                }
            }
            badge.snp.makeConstraints { make in
                make.leading.top.equalToSuperview()
                make.size.equalTo(32)
            }
            number.snp.makeConstraints { make in make.center.equalToSuperview() }
            title.snp.makeConstraints { make in
                make.leading.equalTo(badge.snp.trailing).offset(18)
                make.trailing.equalToSuperview()
                make.centerY.equalTo(badge)
            }
            detail.snp.makeConstraints { make in
                make.leading.trailing.equalTo(title)
                make.top.equalTo(title.snp.bottom).offset(6)
                make.bottom.equalToSuperview()
            }
            badges.append(badge)
            previous = row
        }
        previous?.snp.makeConstraints { make in make.bottom.equalToSuperview() }
        for index in 0..<max(0, badges.count - 1) {
            let connector = Canvas(color: Palette.border, radius: 1)
            connector.setAccessibilityElement(false)
            addSubview(connector, positioned: .below, relativeTo: subviews.first)
            connector.snp.makeConstraints { make in
                make.centerX.equalTo(badges[index])
                make.top.equalTo(badges[index].snp.bottom).offset(6)
                make.bottom.equalTo(badges[index + 1].snp.top).offset(-6)
                make.width.equalTo(2)
            }
        }
    }
}

/// Connects compact step groups with equally sized rules that stop before each badge and title.
@MainActor
private final class OnboardingProgressView: Canvas {

    /// The horizontal layout containing alternating step groups and connector lines.
    private lazy var row: NSStackView = {
        let view = NSStackView()
        view.orientation = .horizontal
        view.alignment = .centerY
        view.distribution = .fill
        view.spacing = 16
        return view
    }()

    /// The circular backgrounds for active, upcoming, and completed step numbers.
    private var badges: [Canvas] = []

    /// The centered step numbers shown before device preparation completes.
    private var numbers: [NSTextField] = []

    /// The native SF Symbols checkmarks shown for completed device preparation.
    private var checkmarks: [NSImageView] = []

    /// The step titles whose color identifies the current stage.
    private var titles: [NSTextField] = []

    /// Composes intrinsic step groups and flexible, equal-width connector lines.
    init() {
        super.init()
        addSubview(row)
        row.snp.makeConstraints { make in make.edges.equalToSuperview() }
        var previousConnector: Canvas?
        for (index, step) in OnboardingRepository.Step.allCases.enumerated() {
            if index > 0 {
                let connector = Canvas(color: Palette.accent.withAlphaComponent(0.16), radius: 0.5)
                connector.setAccessibilityElement(false)
                row.addArrangedSubview(connector)
                connector.snp.makeConstraints { make in
                    make.height.equalTo(1)
                    if let previousConnector { make.width.equalTo(previousConnector) }
                }
                previousConnector = connector
            }
            let badge = Canvas(color: Palette.border, radius: 14)
            let number = makeLabel(size: 15, color: Palette.secondary, weight: .semibold)
            number.alignment = .center
            number.stringValue = String(index + 1)
            number.wantsLayer = true
            number.setAccessibilityElement(false)
            let checkmark = NSImageView()
            checkmark.image = NSImage(
                systemSymbolName: "checkmark",
                accessibilityDescription: nil
            )?.withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
            checkmark.contentTintColor = .white
            checkmark.imageScaling = .scaleProportionallyUpOrDown
            checkmark.wantsLayer = true
            checkmark.alphaValue = 0
            checkmark.setAccessibilityElement(false)
            badge.addSubview(number)
            badge.addSubview(checkmark)
            badge.snp.makeConstraints { make in make.size.equalTo(28) }
            number.snp.makeConstraints { make in make.center.equalToSuperview() }
            checkmark.snp.makeConstraints { make in
                make.center.equalToSuperview()
                make.size.equalTo(14)
            }
            let title = makeLabel(
                step.title,
                size: 16,
                color: Palette.secondary,
                weight: .medium
            )
            title.setContentCompressionResistancePriority(.required, for: .horizontal)
            let group = NSStackView(views: [badge, title])
            group.orientation = .horizontal
            group.alignment = .centerY
            group.spacing = 10
            group.setHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(group)
            badges.append(badge)
            numbers.append(number)
            checkmarks.append(checkmark)
            titles.append(title)
        }
    }

    /// Storyboard decoding is unsupported for this programmatic progress view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Applies green completion badges, a blue active badge, and muted upcoming numbers.
    func update(
        current: OnboardingRepository.Step,
        cameraReady: Bool,
        virtualCameraReady: Bool
    ) {
        for (index, step) in OnboardingRepository.Step.allCases.enumerated() {
            let completed = step == .camera ? cameraReady : step == .virtualCamera ? virtualCameraReady : false
            let active = step == current
            let fill: NSColor = completed ? .systemGreen : active ? Palette.accent : Palette.border
            let numberColor: NSColor = completed || active ? .white : Palette.secondary
            let titleColor = active ? Palette.accent : Palette.secondary
            ControlMotion.setOpacity(completed ? 0 : 1, on: numbers[index])
            ControlMotion.setOpacity(completed ? 1 : 0, on: checkmarks[index])
            ControlMotion.set(
                fill.cgColor,
                for: "backgroundColor",
                on: badges[index].layer,
                in: self
            )
            for (label, color) in [(numbers[index], numberColor), (titles[index], titleColor)] {
                if label.textColor != color {
                    ControlMotion.animate(in: label) { label.animator().textColor = color }
                }
            }
            badges[index].setAccessibilityLabel(
                OnboardingStrings.stepAccessibility(
                    title: step.title,
                    state: completed
                        ? OnboardingStrings.completed
                        : active ? OnboardingStrings.currentStep : OnboardingStrings.upcoming
                )
            )
        }
    }
}

/// Illustrates the user-controlled permission, extension, and meeting camera-selection actions.
@MainActor
private final class OnboardingIllustrationView: Canvas {

    /// Includes screenshot page selection in the modal's keyboard navigation cycle.
    var navigationControls: [NSControl] { screenshots.isHidden ? [] : screenshots.navigationControls }

    /// The user-supplied temporary camera-step image, independently replaceable from extension screenshots.
    private lazy var cameraScreenshot: OnboardingScreenshotView = {
        let view = OnboardingScreenshotView(
            resourceName: "OnboardingCameraPermission",
            crop: NSRect(x: 0, y: 0, width: 1, height: 1)
        )
        view.setAccessibilityLabel(OnboardingStrings.guideFaceNowSetupIllustration)
        return view
    }()

    /// The installation illustration and supplied macOS screenshots for the extension walkthrough.
    private lazy var screenshots: OnboardingVirtualCameraScreenshotsView = {
        let view = OnboardingVirtualCameraScreenshotsView()
        return view
    }()

    /// The mock system surface inside the neutral illustration panel.
    private lazy var surface: Canvas = {
        let view = Canvas(color: .white, radius: 16)
        view.layer?.borderWidth = 1
        view.layer?.borderColor = Palette.border.cgColor
        return view
    }()

    /// The stage's application or settings title.
    private lazy var title: NSTextField = {
        let view = wrappingLabel(size: 15, weight: .semibold)
        view.alignment = .center
        return view
    }()

    /// The symbolic context for the illustrated action.
    private lazy var symbol: NSImageView = {
        let view = NSImageView()
        view.contentTintColor = Palette.accent
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityElement(false)
        return view
    }()

    /// The neutral unselected option or permission explanation.
    private lazy var detail: NSTextField = {
        let view = wrappingLabel(size: 13, color: Palette.secondary)
        view.alignment = .center
        return view
    }()

    /// The highlighted settings action or real virtual-camera menu entry.
    private lazy var highlight: Canvas = {
        let view = Canvas(color: Palette.accent.withAlphaComponent(0.07), radius: 10)
        view.layer?.borderWidth = 1.5
        view.layer?.borderColor = Palette.accent.cgColor
        return view
    }()

    /// The explanatory action shown inside the highlighted illustration row.
    private lazy var action: NSTextField = {
        let view = wrappingLabel(size: 13, color: Palette.accent, weight: .semibold)
        view.alignment = .center
        return view
    }()

    /// The lower caption distinguishes the illustration from live system controls.
    private lazy var caption: NSTextField = {
        let view = wrappingLabel(size: 11, color: Palette.secondary)
        view.alignment = .center
        return view
    }()

    /// Composes explanatory diagrams and a dedicated virtual-camera screenshot walkthrough.
    init() {
        super.init(color: Palette.surface, radius: 18)
        [surface, caption, screenshots, cameraScreenshot].forEach(addSubview)
        screenshots.snp.makeConstraints { make in make.edges.equalToSuperview().inset(16) }
        cameraScreenshot.snp.makeConstraints { make in make.edges.equalToSuperview().inset(24) }
        [title, symbol, detail, highlight].forEach(surface.addSubview)
        highlight.addSubview(action)
        surface.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.centerY.equalToSuperview().offset(-12)
            make.height.equalTo(266)
        }
        title.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview().inset(20)
        }
        symbol.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(title.snp.bottom).offset(20)
            make.size.equalTo(58)
        }
        detail.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(18)
            make.top.equalTo(symbol.snp.bottom).offset(16)
        }
        highlight.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview().inset(16)
            make.height.equalTo(60)
        }
        action.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(10)
            make.centerY.equalToSuperview()
        }
        caption.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.top.equalTo(surface.snp.bottom).offset(16)
        }
    }

    /// Storyboard decoding is unsupported for this programmatic illustration.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Updates only meeting-app copy when its native selector changes.
    func updateVideoCallApp(
        _ app: String
    ) {
        title.stringValue = OnboardingStrings.videoSettingsTitle(app: app)
    }

    /// Highlights the correct action while keeping all actual system actions in the dialog footer.
    func update(
        step: OnboardingRepository.Step,
        app: String,
        preparationTitle: String,
        primaryTitle: String,
        preparationDetail: String
    ) {
        if step == .virtualCamera {
            screenshots.update(
                heading: preparationTitle,
                actionTitle: primaryTitle,
                detail: preparationDetail
            )
        }
        let showsScreenshots: Bool
        if #available(macOS 15, *) {
            showsScreenshots = step == .virtualCamera
        } else {
            showsScreenshots = false
        }
        screenshots.isHidden = !showsScreenshots
        cameraScreenshot.isHidden = step != .camera
        surface.isHidden = showsScreenshots || step == .camera
        caption.isHidden = showsScreenshots || step == .camera
        let symbolName: String
        switch step {
        case .camera:
            title.stringValue = OnboardingStrings.guideFaceNowWouldLikeToAccessTheCamera
            symbolName = "camera.fill"
            detail.stringValue = OnboardingStrings.guideFaceNowUsesYourCameraForRealTimeEffects
            action.stringValue = OnboardingStrings.guideChooseAllow
            caption.stringValue = OnboardingStrings.guideCameraPermissionMacOSDialogIllustration
        case .virtualCamera:
            title.stringValue = OnboardingStrings.guideSystemSettings
            symbolName = "gearshape.fill"
            if #available(macOS 15, *) {
                detail.stringValue = OnboardingStrings.guideGeneralLoginItemsExtensionsNCameraExtensions
            } else {
                detail.stringValue = OnboardingStrings.guidePrivacySecurityNAllowTheFaceNowSystemExtension
            }
            action.stringValue = OnboardingStrings.guideEnableFaceNowDone
            caption.stringValue = OnboardingStrings.guideReturnToFaceNowReadinessIsCheckedAutomatically
        case .videoCalls:
            updateVideoCallApp(app)
            symbolName = "video.fill"
            detail.stringValue = OnboardingStrings.guideCameraNChooseYourVideoInput
            action.stringValue = OnboardingStrings.selectedCameraIllustration(
                name: VirtualCameraConfiguration.deviceName
            )
            caption.stringValue = OnboardingStrings.guideCameraMenuIllustrationTheLayoutVariesByApp
        }
        symbol.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }
}

/// Mirrors the three extension setup instructions with one corresponding walkthrough page each.
@MainActor
private final class OnboardingVirtualCameraScreenshotsView: Canvas {

    /// The page selectors exposed to the owning modal's explicit focus cycle.
    var navigationControls: [NSControl] { tabs.selectionControls }

    /// Uses the same shared pill group, typography, and selection appearance as generation modes.
    private lazy var tabs: TabSwitcher = {
        let view = TabSwitcher(
            titles: [
                OnboardingStrings.virtualCamera, OnboardingStrings.noticeOpenSystemSettings,
                OnboardingStrings.guideEnableFaceNow,
            ],
            distribution: .content
        )
        view.font = Typography.font(size: 12, weight: .medium)
        view.horizontalPadding = 8
        view.onSelectionChanged = { [weak self] index in self?.selectPage(index) }
        return view
    }()

    /// Illustrates the initial footer action before the system permission dialog appears.
    private lazy var installation: OnboardingInstallIllustrationView = {
        let view = OnboardingInstallIllustrationView()
        return view
    }()

    /// The original macOS prompt screenshot, scaled proportionally within the guide.
    private lazy var promptImage: OnboardingScreenshotView = {
        let view = OnboardingScreenshotView(
            resourceName: "OnboardingVirtualCameraPermission",
            crop: NSRect(x: 0, y: 0, width: 1, height: 1)
        )
        view.setAccessibilityLabel(OnboardingStrings.guideCameraExtensionPermissionPromptChooseOpenSystemSettings)
        return view
    }()

    /// The settings screenshot focused on the extension sheet while retaining the original asset.
    private lazy var settingsImage: OnboardingScreenshotView = {
        let view = OnboardingScreenshotView(
            resourceName: "OnboardingVirtualCameraSettings",
            crop: NSRect(x: 210.0 / 1181, y: 289.0 / 1333, width: 758.0 / 1181, height: 754.0 / 1333)
        )
        view.setAccessibilityLabel(OnboardingStrings.guideCameraExtensionsEnableFaceNowThenClickDone)
        return view
    }()

    /// The action caption beneath the currently selected screenshot.
    private lazy var caption: NSTextField = {
        let view = wrappingLabel(size: 12, color: Palette.secondary)
        view.alignment = .center
        return view
    }()

    /// Composes the three walkthrough pages without altering system permission or installation state.
    init() {
        super.init()
        [tabs, installation, promptImage, settingsImage, caption].forEach(addSubview)
        tabs.snp.makeConstraints { make in
            make.centerX.top.equalToSuperview()
            make.width.lessThanOrEqualToSuperview()
            make.width.equalTo(tabs.preferredWidth).priority(490)
            make.height.equalTo(42)
        }
        caption.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
        }
        [installation, promptImage, settingsImage].forEach { image in
            image.snp.makeConstraints { make in
                make.leading.trailing.equalToSuperview()
                make.top.equalTo(tabs.snp.bottom).offset(14)
                make.bottom.equalTo(caption.snp.top).offset(-12)
            }
        }
        selectPage(0)
    }

    /// Storyboard decoding is unsupported for this programmatic screenshot walkthrough.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Retains the current action's instruction while the user browses the system screenshots.
    private var preparationDetail = OnboardingStrings.clickPrimaryButton(OnboardingStrings.install)

    /// Reflects the same derived instruction and primary button as the guide footer.
    func update(
        heading: String,
        actionTitle: String,
        detail: String
    ) {
        installation.update(heading: heading, actionTitle: actionTitle)
        preparationDetail = detail
        if tabs.selectedIndex == 0 { caption.stringValue = detail }
    }

    /// Switches the displayed screenshot and its matching action caption.
    private func selectPage(
        _ page: Int
    ) {
        guard (0...2).contains(page) else { return }
        if tabs.selectedIndex != page { tabs.selectedIndex = page }
        installation.isHidden = page != 0
        promptImage.isHidden = page != 1
        settingsImage.isHidden = page != 2
        switch page {
        case 0: caption.stringValue = preparationDetail
        case 1: caption.stringValue = OnboardingStrings.guideClickOpenSystemSettingsInTheMacOSDialog
        default: caption.stringValue = OnboardingStrings.guideTurnOnTheSwitchNextToFaceNowThenClick
        }
    }
}

/// Illustrates the first setup action while the other two pages show actual macOS screenshots.
@MainActor
private final class OnboardingInstallIllustrationView: Canvas {

    /// The centered white setup illustration inside the screenshot panel.
    private lazy var surface: Canvas = {
        let view = Canvas(color: .white, radius: 16)
        view.layer?.borderWidth = 1
        view.layer?.borderColor = Palette.border.cgColor
        return view
    }()

    /// The native virtual-camera symbol above the installation action.
    private lazy var symbol: NSImageView = {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)
        view.contentTintColor = Palette.accent
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityElement(false)
        return view
    }()

    /// The heading matching the first timeline instruction.
    private lazy var title: NSTextField = {
        let view = wrappingLabel(size: 15, weight: .semibold)
        view.stringValue = OnboardingStrings.guideInstallVirtualCamera
        view.alignment = .center
        return view
    }()

    /// The decorative primary action; actual installation remains in the dialog footer.
    private lazy var action: Canvas = {
        let view = Canvas(color: Palette.accent, radius: 12)
        return view
    }()

    /// The exact button name used by the real installation action.
    private lazy var actionTitle: NSTextField = {
        let view = makeLabel(OnboardingStrings.install, size: 14, color: .white, weight: .semibold)
        return view
    }()

    /// Composes a noninteractive preview without duplicating an installation control.
    init() {
        super.init()
        addSubview(surface)
        [symbol, title, action].forEach(surface.addSubview)
        action.addSubview(actionTitle)
        surface.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalToSuperview().offset(-32).priority(490)
            make.width.lessThanOrEqualTo(360)
            make.height.equalTo(220)
        }
        symbol.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(28)
            make.size.equalTo(52)
        }
        title.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(20)
            make.top.equalTo(symbol.snp.bottom).offset(16)
        }
        action.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview().inset(24)
            make.height.equalTo(42)
        }
        actionTitle.snp.makeConstraints { make in make.center.equalToSuperview() }
    }

    /// Renders the current instruction without keeping an independent installation decision.
    func update(
        heading: String,
        actionTitle: String
    ) {
        title.stringValue = heading
        self.actionTitle.stringValue = actionTitle
    }

    /// Storyboard decoding is unsupported for this programmatic illustration.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }
}

/// Draws a proportionally scaled region of an original bundled screenshot without stretching it.
@MainActor
private final class OnboardingScreenshotView: Canvas {

    /// The full-resolution source image supplied for the guide.
    private let image: NSImage?

    /// The visible source region in normalized coordinates measured from the top-left.
    private let crop: NSRect

    /// Retains the original image while focusing the displayed viewport on the relevant system dialog.
    init(
        resourceName: String,
        crop: NSRect
    ) {
        image = NSImage(named: resourceName)
        self.crop = crop
        super.init()
        setAccessibilityRole(.image)
    }

    /// Storyboard decoding is unsupported for this programmatic screenshot view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Fits the relevant screenshot region within the available guide panel using its original aspect ratio.
    override func draw(
        _ dirtyRect: NSRect
    ) {
        super.draw(dirtyRect)
        guard let image, bounds.width > 0, bounds.height > 0 else { return }
        let source = NSRect(
            x: crop.minX * image.size.width,
            y: (1 - crop.maxY) * image.size.height,
            width: crop.width * image.size.width,
            height: crop.height * image.size.height
        )
        let scale = min(bounds.width / source.width, bounds.height / source.height)
        let size = NSSize(width: source.width * scale, height: source.height * scale)
        let destination = NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: destination,
            from: source,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Creates intrinsic, wrapping guide copy that follows the shared font family.
@MainActor
private func wrappingLabel(
    size: CGFloat,
    color: NSColor = Palette.text,
    weight: NSFont.Weight = .regular
) -> NSTextField {
    let view = makeLabel(size: size, color: color, weight: weight)
    view.maximumNumberOfLines = 0
    view.lineBreakMode = .byWordWrapping
    view.cell?.wraps = true
    view.cell?.usesSingleLineMode = false
    view.cell?.isScrollable = false
    view.setContentCompressionResistancePriority(.required, for: .vertical)
    return view
}
