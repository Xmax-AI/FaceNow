//
//  HomeViewController.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Factory
import AppKit
import Combine
import SnapKit

/// Composes repository-backed business views and coordinates persistent page transitions.
@MainActor
final class HomeViewController: NSViewController {

    /// The shared credential owner consumed by the user interface and generation.
    @Injected(\.userRepo) private var userRepo: UserRepository

    /// The presentation decisions derived from the shared business owners.
    private lazy var viewModel: HomeViewModel = {
        let viewModel = HomeViewModel()
        return viewModel
    }()

    /// The login page is retained only while authentication is required.
    private var loginPage: UserLoginViewController?

    /// The home navigation state shared with the module's data consumers.
    @Injected(\.homeRepo) private var homeRepo: HomeRepository

    /// Owns the initial saved-session validation.
    private var accountRestore: Task<Void, Never>?

    /// The generation lifecycle owner, created with the same user settings as the editor.
    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    /// The extension owner refreshed when the application becomes active.
    @Injected(\.virtualCameraRepo) var virtualCameraRepo: VirtualCameraRepository

    /// The window content canvas containing scrolling pages and the error overlay.
    private lazy var root: Canvas = {
        let view = Canvas(color: .white)
        view.frame = NSRect(
            x: 0,
            y: 0,
            width: 1360,
            height: 850
        )
        view.addSubview(scroll)
        view.addSubview(errorView)
        return view
    }()

    /// The scroll container preserving access to content at smaller window sizes.
    private lazy var scroll: NSScrollView = {
        let view = NSScrollView()
        view.drawsBackground = false
        view.hasVerticalScroller = true
        view.scrollerStyle = .overlay
        return view
    }()

    /// The persistent document containing the header and both business pages.
    private lazy var document: Canvas = {
        let view = Canvas()
        return view
    }()

    /// The shared product header containing setup or generation actions.
    private lazy var header: Canvas = {
        let view = Canvas()
        return view
    }()

    /// The product wordmark displayed in the header.
    private lazy var logo: NSImageView = {
        let view = NSImageView()
        view.image = NSImage(named: "XmaxWordmark")
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityLabel("Xmax")
        return view
    }()

    /// The home-only row containing camera setup and user preferences.
    private lazy var homeControls: Canvas = {
        let view = Canvas()
        return view
    }()

    /// The camera selection and extension-setup entry points.
    private lazy var cameraControls: HomeCameraControlsView = {
        let view = HomeCameraControlsView()
        return view
    }()

    /// The credential editor owned by FNUser.
    private lazy var userView: UserAPIKeyView = {
        let view = UserAPIKeyView()
        view.onSignIn = { [weak self] in
            self?.synchronizeLoginPage()
        }
        view.onSignOut = { [weak self] in self?.signOut() }
        return view
    }()

    /// The generation toolbar, retained while the initial page is visible.
    private lazy var toolbar: GenerationToolbarView = {
        let view = GenerationToolbarView()
        view.onWidthChange = { [weak self] in self?.view.needsLayout = true }
        return view
    }()

    /// The initial camera-start experience owned by FNOnboarding.
    private lazy var landing: OnboardingLandingView = {
        let view = OnboardingLandingView()
        view.onStart = { [weak self] in self?.startCamera() }
        return view
    }()

    /// The persistent generation workspace, mounted before camera readiness.
    private lazy var workspace: GenerationWorkspaceView = {
        let view = GenerationWorkspaceView()
        return view
    }()

    /// The home-page product links and follow popover.
    private lazy var footer: HomeFooterView = {
        let view = HomeFooterView()
        return view
    }()

    /// The selectable error notification overlaid on the window content.
    private lazy var errorView: HomeErrorView = {
        let view = HomeErrorView()
        view.onDismiss = { [weak self] in self?.generationRepo.dismissError() }
        return view
    }()

    /// Retains notifications from user, generation, and extension state owners.
    private var observations: Set<AnyCancellable> = []

    /// Coalesces notifications until published values have been assigned.
    private var renderScheduled = false

    /// Prevents an already-enqueued render from rebuilding views during shutdown.
    private var isShuttingDown = false

    /// The last rendered page identity.
    private var displayedSession: Bool?

    /// The last announced error, used to avoid repeated accessibility announcements.
    private var displayedError: String?

    /// The current notification's auto-dismiss task.
    private var errorTask: Task<Void, Never>?

    /// Refreshes elapsed time and interpolation state while the view is visible.
    private var ticker: Task<Void, Never>?

    /// Resolves shared business dependencies before lazily constructing any views.
    init() {
        super.init(
            nibName: nil,
            bundle: nil
        )
    }

    /// Storyboard decoding is unsupported for this programmatic controller.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Mounts both pages once so hidden preview bindings can satisfy SDK readiness.
    override func loadView() {
        view = root
        scroll.documentView = document
        [header, landing, workspace, footer].forEach(document.addSubview)
        [logo, homeControls, toolbar].forEach(header.addSubview)
        [cameraControls, userView].forEach(homeControls.addSubview)

        userRepo.objectWillChange.sink { [weak self] in self?.scheduleRender() }.store(in: &observations)
        homeRepo.objectWillChange.sink { [weak self] in self?.scheduleRender() }.store(in: &observations)
        generationRepo.objectWillChange.sink { [weak self] in self?.scheduleRender() }.store(in: &observations)
        virtualCameraRepo.objectWillChange.sink { [weak self] in self?.scheduleRender() }.store(in: &observations)
        render()
        accountRestore = Task { [weak self] in await self?.userRepo.restore() }
    }

    /// Starts the existing status refresh cadence after the page is attached.
    override func viewDidAppear() {
        super.viewDidAppear()
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.generationRepo.sessionActive {
                    await self.generationRepo.refreshInterpolationState()
                    self.toolbar.update()
                }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
        }
    }

    /// Stops view work before awaiting generation and virtual-output cleanup.
    func shutdown() async {
        isShuttingDown = true
        accountRestore?.cancel()
        accountRestore = nil
        userRepo.cancelPendingOperations()
        loginPage?.shutdown()
        observations.removeAll()
        ticker?.cancel()
        ticker = nil
        errorTask?.cancel()
        errorTask = nil
        cameraControls.closePopover()
        userView.closePopover()
        toolbar.shutdown()
        footer.closePopover()
        workspace.suspendImages()
        await generationRepo.shutdown()
    }

    /// Defers state reads until Combine's pre-assignment notifications have completed.
    private func scheduleRender() {
        guard !renderScheduled, !isShuttingDown else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isShuttingDown else { return }
            self.renderScheduled = false
            self.render()
        }
    }

    /// Routes the explicit Start action after checking actual extension readiness.
    private func startCamera() {
        guard loginPage == nil else { return }
        let requestedAt = DispatchTime.now().uptimeNanoseconds
        Task { [weak self] in
            await self?.viewModel.startCamera(requestedAt: requestedAt)
        }
    }

    /// Applies committed state through each business component without recreating its views.
    private func render() {
        let active = generationRepo.sessionActive
        let pageChanged = displayedSession != active
        let previousCameraWidth = cameraControls.preferredWidth
        let previousUserWidth = userView.preferredWidth(controlHeight: homeControls.bounds.height)
        cameraControls.update()
        userView.settingsLocked = viewModel.settingsLocked
        userView.update()
        toolbar.update()
        landing.update(
            isStarting: viewModel.isStarting,
            canStart: viewModel.canStart,
            unavailableMessage: viewModel.startUnavailableMessage
        )
        workspace.update()
        let needsPageLayout =
            pageChanged || previousCameraWidth != cameraControls.preferredWidth
            || previousUserWidth != userView.preferredWidth(controlHeight: homeControls.bounds.height)
            || displayedError != generationRepo.errorMessage

        homeControls.isHidden = active
        toolbar.isHidden = !active
        landing.isHidden = active
        footer.isHidden = active
        workspace.isHidden = !active
        if pageChanged {
            displayedSession = active
            cameraControls.closePopover()
            userView.closePopover()
            toolbar.closePopover()
            footer.closePopover()
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            view.window?.makeFirstResponder(nil)
        }
        updateError()
        if needsPageLayout { view.needsLayout = true }
        if pageChanged {
            view.layoutSubtreeIfNeeded()
            animateEntry(active ? workspace : landing)
            if !active { animateEntry(footer) }
        }
        if active, view.window != nil { generationRepo.resultViewDidBecomeReady() }
        synchronizeLoginPage()
    }

    /// Shows a full native login page while preserving mounted generation preview bindings.
    private func synchronizeLoginPage() {
        guard isViewLoaded, !isShuttingDown else { return }
        let needsLogin = viewModel.needsLogin
        if needsLogin, loginPage == nil {
            userView.closePopover()
            cameraControls.closePopover()
            let form = UserLoginFormView()
            let page = UserLoginViewController(formView: form)
            form.presenter = page
            loginPage = page
            addChild(page)
            root.addSubview(page.view)
            page.view.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
            scroll.isHidden = true
            errorView.isHidden = true
            page.view.layoutSubtreeIfNeeded()
            if generationRepo.settingsLocked { Task { [weak self] in await self?.generationRepo.close() } }
        } else if !needsLogin, let page = loginPage {
            page.shutdown()
            page.view.removeFromSuperview()
            page.removeFromParent()
            loginPage = nil
            scroll.isHidden = false
            errorView.isHidden = generationRepo.errorMessage == nil
        }
    }

    /// Stops billable generation and virtual output before invalidating account credentials.
    private func signOut() {
        Task { [weak self] in
            await self?.viewModel.signOut()
        }
    }

    /// Announces each new error once and retains the existing auto-dismiss interval.
    private func updateError() {
        let changed = displayedError != generationRepo.errorMessage
        errorView.update(
            message: generationRepo.errorMessage,
            announce: changed
        )
        guard changed else { return }
        displayedError = generationRepo.errorMessage
        errorTask?.cancel()
        guard generationRepo.errorMessage != nil else { return }
        errorTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            self?.generationRepo.dismissError()
        }
    }

    /// Arranges persistent pages while delegating their internal layouts to their modules.
    override func viewDidLayout() {
        super.viewDidLayout()
        scroll.frame = root.bounds
        let width = scroll.contentSize.width
        let height = scroll.contentSize.height
        let contentWidth = max(0, width - 56)
        landing.viewportWidth = width
        let landingHeight = landing.preferredHeight(contentWidth: contentWidth)
        let workspaceHeight = workspace.preferredHeight(contentWidth: contentWidth)
        let logoHeight = min(52, max(34, width * 0.008 + 24))
        let controlHeight = generationRepo.sessionActive ? 36 : min(48, max(35, width * 0.0055 + 26))
        let headerHeight = max(logoHeight, controlHeight) + 8 + 24
        let footerHeight: CGFloat = 56 + 24
        let active = generationRepo.sessionActive
        let minimumHeight =
            active
            ? 16 + headerHeight + workspaceHeight + 48 : 16 + headerHeight + 30 + landingHeight + 30 + footerHeight + 48
        let documentHeight = max(height, minimumHeight)
        let surplus = max(0, documentHeight - minimumHeight)
        document.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: documentHeight
        )
        header.frame = NSRect(
            x: 28,
            y: 16 + (active ? surplus / 2 : 0),
            width: contentWidth,
            height: headerHeight
        )
        layoutHeader(viewportWidth: width)
        landing.frame = NSRect(
            x: 28,
            y: header.frame.maxY + 30 + surplus / 2,
            width: contentWidth,
            height: landingHeight
        )
        workspace.frame = NSRect(
            x: 28,
            y: header.frame.maxY,
            width: contentWidth,
            height: workspaceHeight
        )
        footer.frame = NSRect(
            x: 28,
            y: documentHeight - 48 - footerHeight,
            width: contentWidth,
            height: footerHeight
        )
        errorView.place(in: root.bounds)
    }

    /// Places the setup and generation rows around the same product wordmark.
    private func layoutHeader(
        viewportWidth width: CGFloat
    ) {
        let logoHeight = min(52, max(34, width * 0.008 + 24))
        let controlHeight = min(48, max(35, width * 0.0055 + 26))
        let rowHeight = header.bounds.height - 8 - 24
        logo.frame = NSRect(
            x: 0,
            y: 8 + (rowHeight - logoHeight) / 2,
            width: logoHeight * 552 / 172,
            height: logoHeight
        )
        let cameraWidth = cameraControls.preferredWidth
        let keyWidth = userView.preferredWidth(controlHeight: controlHeight)
        let homeWidth = cameraWidth + 12 + keyWidth
        homeControls.frame = NSRect(
            x: header.bounds.width - homeWidth,
            y: 8 + (rowHeight - controlHeight) / 2,
            width: homeWidth,
            height: controlHeight
        )
        cameraControls.frame = NSRect(
            x: 0,
            y: 0,
            width: cameraWidth,
            height: controlHeight
        )
        userView.frame = NSRect(
            x: cameraWidth + 12,
            y: 0,
            width: keyWidth,
            height: controlHeight
        )
        toolbar.frame = NSRect(
            x: header.bounds.width - toolbar.preferredWidth,
            y: 8 + (rowHeight - 36) / 2,
            width: toolbar.preferredWidth,
            height: 36
        )
    }

    /// Animates only page presentation and honors the system's reduced-motion preference.
    private func animateEntry(
        _ page: NSView
    ) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.45
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let move = CABasicAnimation(keyPath: "transform.translation.y")
        move.fromValue = 14
        move.toValue = 0
        move.duration = 0.45
        move.timingFunction = fade.timingFunction
        page.layer?.add(
            fade,
            forKey: "pageEntryOpacity"
        )
        page.layer?.add(
            move,
            forKey: "pageEntryPosition"
        )
    }
}
