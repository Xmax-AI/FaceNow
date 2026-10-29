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
        [title, subtitle, timeline].forEach {
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

    /// Owns every point in the overlay, including gaps between native controls and exit frames.
    override func hitTest(
        _ point: NSPoint
    ) -> NSView? {
        guard !isHidden, bounds.contains(convert(point, from: superview)) else { return nil }
        if isDismissing { return self }
        return super.hitTest(point) ?? self
    }

    /// Consumes blank-area presses instead of forwarding them outside the modal responder chain.
    override func mouseDown(
        with event: NSEvent
    ) {}

    /// Keeps blank-area releases inside the modal.
    override func mouseUp(
        with event: NSEvent
    ) {}

    /// Keeps drags that start in modal whitespace from reaching the covered page.
    override func mouseDragged(
        with event: NSEvent
    ) {}

    /// Prevents force clicks on modal whitespace from invoking underlying link previews.
    override func pressureChange(
        with event: NSEvent
    ) {}

    /// Stops unused scroll events after the modal's own scroll view has handled them.
    override func scrollWheel(
        with event: NSEvent
    ) {}

    /// Fades the backdrop and card independently while the card decelerates into its centered position.
    func animatePresentation(
        visible: Bool
    ) {
        isDismissing = !visible
        if isDismissing { window?.makeFirstResponder(self) }
        ControlMotion.setModalVisible(
            visible,
            backdrop: backdrop,
            card: card,
            in: self
        ) {
            card.snp.updateConstraints { make in
                make.centerY.equalToSuperview().offset(visible ? 0 : 24)
            }
        }
    }

    /// Reflects committed preparation state without rebuilding controls or their focus.
    func update(
        model: OnboardingFlowViewModel
    ) {
        let repo = model.onboardingRepo
        progress.update(
            current: repo.step,
            cameraReady: repo.cameraReady,
            virtualCameraReady: repo.virtualCameraReady
        )
        previous.isHidden = repo.step == .camera
        later.isHidden = !model.showsSetupLater
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
            subtitle.stringValue = OnboardingStrings.videoCallsSubtitle
            timeline.update(items: model.videoCallInstructions.map { .init(title: $0.title, detail: $0.detail) })
        }
        illustration.update(
            step: repo.step,
            explanation: model.preparationExplanation,
            virtualCameraPages: model.virtualCameraGuidePages
        )
        let controls: [NSControl] =
            ([closeButton]
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
    var navigationControls: [NSControl] {
        if !videoCalls.isHidden { return videoCalls.navigationControls }
        return screenshots.isHidden ? [] : screenshots.navigationControls
    }

    /// The edition-specific camera-access prompt, separate from virtual-camera extension screenshots.
    private lazy var cameraScreenshot: OnboardingScreenshotView = {
        #if OVERSEA
            let resourceName = "OnboardingCameraPermissionOversea"
        #else
            let resourceName = "OnboardingCameraPermission"
        #endif
        let view = OnboardingScreenshotView(
            resourceName: resourceName,
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

    /// Displays the three original video-calling examples with names, captions, and pagination.
    private lazy var videoCalls: VideoCallsGuideView = {
        let view = VideoCallsGuideView()
        return view
    }()

    /// Explains the current state when the guide has no corresponding screenshot.
    private lazy var explanation: OnboardingExplanationView = {
        let view = OnboardingExplanationView()
        return view
    }()

    /// Composes supplied screenshots and a text fallback without simulated controls.
    init() {
        super.init(color: Palette.surface, radius: 18)
        [explanation, screenshots, cameraScreenshot, videoCalls].forEach(addSubview)
        screenshots.snp.makeConstraints { make in make.edges.equalToSuperview().inset(16) }
        cameraScreenshot.snp.makeConstraints { make in make.edges.equalToSuperview().inset(24) }
        explanation.snp.makeConstraints { make in make.edges.equalToSuperview() }
        videoCalls.snp.makeConstraints { make in make.edges.equalToSuperview().inset(16) }
    }

    /// Storyboard decoding is unsupported for this programmatic illustration.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Displays only the pages derived from the current preparation action.
    func update(
        step: OnboardingRepository.Step,
        explanation: String,
        virtualCameraPages: [OnboardingFlowViewModel.VirtualCameraGuidePage]
    ) {
        if step == .virtualCamera {
            screenshots.update(explanation: explanation, pages: virtualCameraPages)
        }
        let showsScreenshots: Bool
        if #available(macOS 15, *) {
            showsScreenshots = step == .virtualCamera && virtualCameraPages.count > 1
        } else {
            showsScreenshots = false
        }
        screenshots.isHidden = !showsScreenshots
        cameraScreenshot.isHidden = step != .camera
        videoCalls.isHidden = step != .videoCalls
        self.explanation.isHidden = showsScreenshots || step == .camera || step == .videoCalls
        if step != .videoCalls { self.explanation.update(explanation) }
    }
}

/// Renders the current extension instructions without retaining obsolete setup pages.
@MainActor
private final class OnboardingVirtualCameraScreenshotsView: Canvas {

    /// The page controls exposed to the owning modal's explicit focus cycle.
    var navigationControls: [NSControl] {
        pages.count > 1 ? [previousPage] + pageDots.filter { !$0.isHidden } + [nextPage] : []
    }

    /// Preserves the selected page while its preparation instructions remain relevant.
    private var selectedPage = 0

    /// The view model supplies the exact pages required by the current action.
    private var pages: [OnboardingFlowViewModel.VirtualCameraGuidePage] = [.explanation]

    /// Preserves the state explanation while the user browses the recovery pages.
    private var currentExplanation = ""

    /// Keeps the three image selectors centered beneath their caption.
    private lazy var pagination: NSStackView = {
        let view = NSStackView()
        view.orientation = .horizontal
        view.alignment = .centerY
        view.spacing = 2
        view.detachesHiddenViews = true
        return view
    }()

    /// Returns to the previous image, wrapping from the first image to the last.
    private lazy var previousPage: Button = {
        let view = Button(style: .plain)
        view.symbolName = "chevron.left"
        view.iconSize = 12
        view.centersSymbolVisually = true
        view.showsShadow = false
        view.cornerRadius = 14
        view.hoverBackgroundColor = Palette.border.withAlphaComponent(0.5)
        view.setAccessibilityLabel(OnboardingStrings.previousGuideImage)
        view.onClick = { [weak self] in
            guard let self else { return }
            self.movePage(by: -1)
        }
        return view
    }()

    /// At most three relevant pages retain a larger native button hit area.
    private lazy var pageDots: [Button] = {
        let titles = [
            OnboardingStrings.virtualCamera, OnboardingStrings.noticeOpenSystemSettings,
            OnboardingStrings.guideEnableFaceNow,
        ]
        return titles.enumerated().map { index, title in
            let view = Button(style: .plain)
            view.symbolName = "circle.fill"
            view.iconSize = 7
            view.centersSymbolVisually = true
            view.showsShadow = false
            view.cornerRadius = 12
            view.hoverBackgroundColor = Palette.border.withAlphaComponent(0.5)
            view.setAccessibilityLabel(title)
            view.onClick = { [weak self] in self?.selectPage(index) }
            return view
        }
    }()

    /// Advances to the next image, wrapping from the last image to the first.
    private lazy var nextPage: Button = {
        let view = Button(style: .plain)
        view.symbolName = "chevron.right"
        view.iconSize = 12
        view.centersSymbolVisually = true
        view.showsShadow = false
        view.cornerRadius = 14
        view.hoverBackgroundColor = Palette.border.withAlphaComponent(0.5)
        view.setAccessibilityLabel(OnboardingStrings.nextGuideImage)
        view.onClick = { [weak self] in
            guard let self else { return }
            self.movePage(by: 1)
        }
        return view
    }()

    /// Explains the current installation or connection state without a placeholder diagram.
    private lazy var explanation: OnboardingExplanationView = {
        let view = OnboardingExplanationView()
        return view
    }()

    /// The original macOS prompt screenshot, scaled proportionally within the guide.
    private lazy var promptImage: OnboardingScreenshotView = {
        #if OVERSEA
            let resourceName = "OnboardingVirtualCameraPermissionOversea"
        #else
            let resourceName = "OnboardingVirtualCameraPermission"
        #endif
        let view = OnboardingScreenshotView(
            resourceName: resourceName,
            crop: NSRect(x: 0, y: 0, width: 1, height: 1)
        )
        view.setAccessibilityLabel(OnboardingStrings.guideCameraExtensionPermissionPromptChooseOpenSystemSettings)
        return view
    }()

    /// The settings screenshot focused on the extension sheet while retaining the original asset.
    private lazy var settingsImage: OnboardingScreenshotView = {
        #if OVERSEA
            let resourceName = "OnboardingVirtualCameraSettingsOversea"
        #else
            let resourceName = "OnboardingVirtualCameraSettings"
        #endif
        let view = OnboardingScreenshotView(
            resourceName: resourceName,
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
        [explanation, promptImage, settingsImage, caption, pagination].forEach(addSubview)
        ([previousPage] + pageDots + [nextPage]).forEach(pagination.addArrangedSubview)
        [previousPage, nextPage].forEach { button in
            button.snp.makeConstraints { make in make.size.equalTo(28) }
        }
        pageDots.forEach { button in
            button.snp.makeConstraints { make in make.size.equalTo(24) }
        }
        pagination.snp.makeConstraints { make in
            make.centerX.bottom.equalToSuperview()
            make.height.equalTo(28)
        }
        caption.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(pagination.snp.top).offset(-12)
        }
        [explanation, promptImage, settingsImage].forEach { image in
            image.snp.makeConstraints { make in
                make.leading.trailing.top.equalToSuperview()
                make.bottom.equalTo(caption.snp.top).offset(-12)
            }
        }
        selectPage(0)
    }

    /// Storyboard decoding is unsupported for this programmatic screenshot walkthrough.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Resets pagination when the applicable instructions change, including completion.
    func update(
        explanation: String,
        pages: [OnboardingFlowViewModel.VirtualCameraGuidePage]
    ) {
        currentExplanation = explanation
        let nextPages = pages.isEmpty ? [.explanation] : pages
        let pagesChanged = self.pages != nextPages
        self.pages = nextPages
        pagination.isHidden = nextPages.count < 2
        for (index, dot) in pageDots.enumerated() {
            dot.isHidden = !nextPages.indices.contains(index)
            guard !dot.isHidden else { continue }
            switch nextPages[index] {
            case .explanation: dot.setAccessibilityLabel(OnboardingStrings.virtualCamera)
            case .permissionPrompt: dot.setAccessibilityLabel(OnboardingStrings.noticeOpenSystemSettings)
            case .settings: dot.setAccessibilityLabel(OnboardingStrings.guideEnableFaceNow)
            case .recoverySettings: dot.setAccessibilityLabel(OnboardingStrings.guideRestartVirtualCamera)
            }
        }
        selectPage(pagesChanged ? 0 : selectedPage)
    }

    /// Wraps within the currently available pages rather than a fixed screenshot count.
    private func movePage(
        by offset: Int
    ) {
        guard pages.count > 1 else { return }
        selectPage((selectedPage + offset + pages.count) % pages.count)
    }

    /// Switches the displayed screenshot and its matching action caption.
    private func selectPage(
        _ page: Int
    ) {
        guard pages.indices.contains(page) else { return }
        selectedPage = page
        for (index, dot) in pageDots.enumerated() {
            dot.foregroundColor = index == page ? Palette.accent : Palette.secondary.withAlphaComponent(0.35)
            dot.setAccessibilityValue(index == page ? 1 : 0)
        }
        let content = pages[page]
        explanation.isHidden = content != .explanation
        caption.isHidden = !explanation.isHidden
        promptImage.isHidden = content != .permissionPrompt
        settingsImage.isHidden = content != .settings && content != .recoverySettings
        explanation.update(currentExplanation)
        switch content {
        case .explanation: caption.stringValue = ""
        case .permissionPrompt: caption.stringValue = OnboardingStrings.guideClickOpenSystemSettingsInTheMacOSDialog
        case .settings: caption.stringValue = OnboardingStrings.guideTurnOnTheSwitchNextToFaceNowThenClick
        case .recoverySettings: caption.stringValue = OnboardingStrings.guideToggleVirtualCamera
        }
    }
}

/// Presents a readable state explanation and resolution without decorative controls.
@MainActor
private final class OnboardingExplanationView: Canvas {

    /// The state-specific paragraph uses the same typography as other guide descriptions.
    private lazy var text: NSTextField = {
        let view = wrappingLabel(size: 15, color: Palette.secondary)
        view.alignment = .left
        return view
    }()

    /// Centers the explanation vertically while preserving comfortable margins for wrapped copy.
    init() {
        super.init()
        addSubview(text)
        text.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(32)
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview().offset(24)
            make.bottom.lessThanOrEqualToSuperview().inset(24)
        }
    }

    /// Updates complete paragraphs only when the presented state actually changes.
    func update(
        _ explanation: String
    ) {
        guard text.stringValue != explanation else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        text.attributedStringValue = NSAttributedString(
            string: explanation,
            attributes: [
                .font: Typography.font(size: 15),
                .foregroundColor: Palette.secondary,
                .paragraphStyle: paragraph,
            ]
        )
    }

    /// Storyboard decoding is unsupported for this programmatic explanation.
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
