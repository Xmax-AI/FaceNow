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

    /// Refreshes credits while a validated account is displayed in the home header.
    private var accountRefresh: Task<Void, Never>?

    /// The generation lifecycle owner, created with the same user settings as the editor.
    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    /// The extension owner refreshed when the application becomes active.
    @Injected(\.virtualCameraRepo) var virtualCameraRepo: VirtualCameraRepository

    /// The preparation presentation model shared with the persistent home reminder.
    private lazy var onboardingModel: OnboardingFlowViewModel = {
        let viewModel = OnboardingFlowViewModel()
        return viewModel
    }()

    /// The currently mounted modal preparation guide.
    private var onboardingPage: OnboardingViewController?

    /// Limits automatic presentation to one attempt per authenticated visit to home.
    private var onboardingAutoPresented = false

    /// Delays automatic preparation until the login-to-home transition has settled.
    private var onboardingPresentationTask: Task<Void, Never>?

    /// The window content canvas containing scrolling pages and the error overlay.
    private lazy var root: Canvas = {
        let view = Canvas(color: .white)
        view.addSubview(scroll)
        view.addSubview(errorView)
        view.addSubview(signInToast)
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
        view.onShowOnboarding = { [weak self] step in self?.showOnboarding(at: step) }
        return view
    }()

    /// The credential editor owned by FNUser.
    private lazy var userView: UserAPIKeyView = {
        let view = UserAPIKeyView()
        view.onSignIn = { [weak self] in
            #if DEBUG
                self?.viewModel.endHomePreview()
            #endif
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
        view.onPreview = { [weak self] in self?.toggleCameraPreview() }
        view.onSetup = { [weak self] in self?.showOnboarding() }
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
    private lazy var errorView: HomeToastView = {
        let view = HomeToastView()
        view.onDismiss = { [weak self] in self?.generationRepo.dismissError() }
        return view
    }()

    /// The success notification retained above the newly authenticated home page.
    private lazy var signInToast: HomeToastView = {
        let view = HomeToastView()
        view.onDismiss = { [weak self] in self?.dismissSignInToast() }
        return view
    }()

    /// Whether the success toast temporarily owns the notification position.
    private var signInToastVisible = false

    /// Removes the explicit-login notification after its short display interval.
    private var signInToastTask: Task<Void, Never>?

    /// Retains notifications from user, generation, and extension state owners.
    private var observations: Set<AnyCancellable> = []

    /// Coalesces notifications until published values have been assigned.
    private var renderScheduled = false

    /// Prevents an already-enqueued render from rebuilding views during shutdown.
    private var isShuttingDown = false

    /// Avoids reapplying unchanged responsive constraint metrics.
    private var layoutSignature = ""

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
        [logo, homeControls, toolbar, userView].forEach(header.addSubview)
        homeControls.addSubview(cameraControls)
        configureLayout()

        userRepo.objectWillChange.sink { [weak self] in self?.scheduleRender() }.store(in: &observations)
        homeRepo.objectWillChange.sink { [weak self] in self?.scheduleRender() }.store(in: &observations)
        generationRepo.objectWillChange.sink { [weak self] in self?.scheduleRender() }.store(in: &observations)
        virtualCameraRepo.objectWillChange.sink { [weak self] in self?.scheduleRender() }.store(in: &observations)
        onboardingModel.objectWillChange.sink { [weak self] in self?.scheduleRender() }.store(in: &observations)
        onboardingModel.onboardingRepo.objectWillChange.sink { [weak self] in self?.scheduleRender() }
            .store(in: &observations)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isShuttingDown else { return }
                    self.generationRepo.refreshCameras()
                    self.scheduleRender()
                }
            }.store(in: &observations)
        userRepo.signInCompleted.sink { [weak self] in
            // The profile's queued render finishes the login-to-home transition first.
            DispatchQueue.main.async { [weak self] in self?.showSignInToast() }
        }.store(in: &observations)
        render()
        accountRestore = Task { [weak self] in await self?.userRepo.restore() }
    }

    /// Starts the existing status refresh cadence after the page is attached.
    override func viewDidAppear() {
        super.viewDidAppear()
        synchronizeOnboarding()
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

    /// The pending handoff from local preview to generation capture.
    private var cameraStartTask: Task<Void, Never>?

    /// Stops view work before awaiting generation and virtual-output cleanup.
    func shutdown() async {
        isShuttingDown = true
        cameraStartTask?.cancel()
        dismissOnboarding(animated: false)
        accountRestore?.cancel()
        accountRestore = nil
        accountRefresh?.cancel()
        accountRefresh = nil
        userRepo.cancelPendingOperations()
        loginPage?.shutdown()
        observations.removeAll()
        ticker?.cancel()
        ticker = nil
        errorTask?.cancel()
        errorTask = nil
        signInToastTask?.cancel()
        signInToastTask = nil
        signInToast.shutdown()
        errorView.shutdown()
        cameraControls.closePopover()
        userView.shutdown()
        toolbar.shutdown()
        footer.closePopover()
        workspace.suspendImages()
        await homeRepo.stopPreview()
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
        guard loginPage == nil, cameraStartTask == nil, !isShuttingDown else { return }
        guard viewModel.canStart else {
            generationRepo.showSetupError(viewModel.startUnavailableMessage)
            return
        }
        let requestedAt = DispatchTime.now().uptimeNanoseconds
        cameraStartTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.cameraStartTask = nil
                self.scheduleRender()
            }
            await self.homeRepo.stopPreview()
            guard !Task.isCancelled, !self.isShuttingDown, !self.viewModel.needsLogin,
                self.onboardingPage == nil
            else { return }
            await self.viewModel.startCamera(requestedAt: requestedAt)
        }
        scheduleRender()
    }

    /// Toggles local video without starting generation, network streaming, or microphone capture.
    private func toggleCameraPreview() {
        guard !isShuttingDown, !viewModel.needsLogin, loginPage == nil, onboardingPage == nil,
            !generationRepo.settingsLocked, !generationRepo.isClosing, cameraStartTask == nil,
            !homeRepo.isPreviewLoading
        else { return }
        Task { [weak self] in
            guard let self, !self.isShuttingDown, !self.viewModel.needsLogin,
                self.onboardingPage == nil, !self.generationRepo.settingsLocked,
                !self.generationRepo.isClosing, self.cameraStartTask == nil
            else { return }
            if self.homeRepo.isPreviewing {
                await self.homeRepo.stopPreview()
            } else {
                do {
                    try await self.homeRepo.startPreview(deviceID: self.generationRepo.cameraID)
                } catch is CancellationError {
                    return
                } catch {
                    guard !self.isShuttingDown, !self.viewModel.needsLogin else { return }
                    self.generationRepo.showSetupError(error.localizedDescription)
                }
            }
        }
    }

    /// Applies committed state through each business component without recreating its views.
    private func render() {
        onboardingModel.synchronize()
        #if DEBUG
            if userRepo.canAccessHome { viewModel.endHomePreview() }
        #endif
        let active = generationRepo.sessionActive
        if let deviceID = homeRepo.previewDeviceID,
            viewModel.needsLogin || generationRepo.settingsLocked || generationRepo.isClosing
                || deviceID != generationRepo.cameraID
        {
            Task { [weak self] in await self?.homeRepo.stopPreview() }
        }
        let pageChanged = displayedSession != active
        let previousCameraWidth = cameraControls.preferredWidth
        let previousUserWidth = userView.preferredWidth(controlHeight: homeControls.bounds.height)
        cameraControls.update()
        userView.settingsLocked = viewModel.settingsLocked
        userView.update()
        toolbar.update()
        landing.update(
            isStarting: viewModel.isStarting || cameraStartTask != nil,
            canStart: viewModel.canStart,
            unavailableMessage: viewModel.startUnavailableMessage
        )
        landing.updatePreparation(model: onboardingModel)
        landing.updatePreview(
            session: homeRepo.cameraPreview.session,
            isPreviewing: homeRepo.isPreviewing,
            isLoading: homeRepo.isPreviewLoading,
            isAvailable: !generationRepo.settingsLocked && !generationRepo.isClosing && cameraStartTask == nil
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
        if pageChanged, !viewModel.needsLogin, loginPage == nil, view.window != nil {
            view.layoutSubtreeIfNeeded()
            animateEntry(active ? workspace : landing)
            if !active { animateEntry(footer) }
        }
        if active, view.window != nil { generationRepo.resultViewDidBecomeReady() }
        synchronizeLoginPage()
        synchronizeOnboarding()
        synchronizeAccountRefresh()
    }

    /// Schedules unfinished preparation half a second after the authenticated home page becomes available.
    private func synchronizeOnboarding() {
        guard !isShuttingDown else { return }
        if viewModel.needsLogin {
            onboardingAutoPresented = false
            dismissOnboarding(animated: false)
            return
        }
        guard userRepo.canAccessHome, view.window != nil, !generationRepo.sessionActive,
            !onboardingAutoPresented
        else { return }
        onboardingAutoPresented = true
        guard !onboardingModel.onboardingRepo.hasCompletedGuide else { return }
        onboardingPresentationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.onboardingPresentationTask = nil
            guard !self.isShuttingDown, self.userRepo.canAccessHome, !self.viewModel.needsLogin,
                self.loginPage == nil, self.view.window != nil, !self.generationRepo.settingsLocked,
                self.onboardingPage == nil, !self.onboardingModel.onboardingRepo.hasCompletedGuide
            else { return }
            self.showOnboarding()
        }
    }

    /// Mounts the guide above the home page while retaining all existing preview resources.
    private func showOnboarding(
        at step: OnboardingRepository.Step? = nil
    ) {
        guard !isShuttingDown, !viewModel.needsLogin, view.window != nil else { return }
        Task { [weak self] in await self?.homeRepo.stopPreview() }
        onboardingPresentationTask?.cancel()
        onboardingPresentationTask = nil
        onboardingAutoPresented = true
        cameraControls.closePopover()
        userView.closePopover()
        toolbar.closePopover()
        footer.closePopover()
        onboardingModel.refresh()
        onboardingModel.onboardingRepo.begin(at: step)
        if let page = onboardingPage {
            page.present()
            return
        }
        let page = OnboardingViewController(viewModel: onboardingModel)
        page.onDismiss = { [weak self] in self?.dismissOnboarding() }
        onboardingPage = page
        addChild(page)
        root.addSubview(page.view)
        page.view.snp.makeConstraints { make in make.edges.equalToSuperview() }
        root.layoutSubtreeIfNeeded()
        page.present()
    }

    /// Releases modal work on deferral, completion, sign-out, or application shutdown.
    private func dismissOnboarding(
        animated: Bool = true
    ) {
        onboardingPresentationTask?.cancel()
        onboardingPresentationTask = nil
        onboardingModel.onboardingRepo.dismiss()
        guard let page = onboardingPage else { return }
        page.dismiss(animated: animated) { [weak self, weak page] in
            guard let self, let page, self.onboardingPage === page else { return }
            page.shutdown()
            page.view.removeFromSuperview()
            page.removeFromParent()
            self.onboardingPage = nil
            self.view.window?.makeFirstResponder(nil)
        }
    }

    /// Starts a bounded refresh cadence and stops it when the account leaves the home page.
    private func synchronizeAccountRefresh() {
        guard userRepo.canAccessHome else {
            accountRefresh?.cancel()
            accountRefresh = nil
            return
        }
        guard accountRefresh == nil else { return }
        accountRefresh = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.isShuttingDown, self.userRepo.canAccessHome else { return }
                await self.userRepo.refreshCredits()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }

    /// Shows a full native login page while preserving mounted generation preview bindings.
    private func synchronizeLoginPage() {
        guard isViewLoaded, !isShuttingDown else { return }
        let needsLogin = viewModel.needsLogin
        if needsLogin, loginPage == nil {
            dismissSignInToast()
            userView.closePopover()
            cameraControls.closePopover()
            let form = UserLoginFormView()
            let page = UserLoginViewController(formView: form)
            #if DEBUG
                page.onSkip = { [weak self] in
                    guard let self else { return }
                    self.viewModel.previewHome()
                    self.render()
                }
            #endif
            form.presenter = page
            loginPage = page
            addChild(page)
            root.addSubview(page.view)
            page.view.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
            scroll.isHidden = true
            errorView.isHidden = true
            if root.window != nil {
                root.layoutSubtreeIfNeeded()
                animateEntry(page.view)
            }
            if generationRepo.settingsLocked { Task { [weak self] in await self?.generationRepo.close() } }
        } else if !needsLogin, let page = loginPage {
            page.shutdown()
            page.view.removeFromSuperview()
            page.removeFromParent()
            loginPage = nil
            scroll.isHidden = false
            errorView.isHidden = generationRepo.errorMessage == nil
            if root.window != nil {
                root.layoutSubtreeIfNeeded()
                animateEntry(document)
            }
        }
    }

    /// Stops billable generation and virtual output before invalidating account credentials.
    private func signOut() {
        dismissOnboarding()
        cameraStartTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            await self.homeRepo.stopPreview()
            await self.viewModel.signOut()
        }
    }

    /// Announces each new error once and retains the existing auto-dismiss interval.
    private func updateError() {
        let changed = displayedError != generationRepo.errorMessage
        if changed, generationRepo.errorMessage != nil { dismissSignInToast() }
        errorView.update(
            message: generationRepo.errorMessage,
            announce: changed
        )
        if signInToastVisible { errorView.isHidden = true }
        guard changed else { return }
        displayedError = generationRepo.errorMessage
        errorTask?.cancel()
        guard generationRepo.errorMessage != nil else { return }
        errorTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            self?.generationRepo.dismissError()
        }
    }

    /// Shows one success toast only for an explicit, validated login event.
    private func showSignInToast() {
        guard !isShuttingDown, userRepo.canAccessHome else { return }
        synchronizeLoginPage()
        signInToastTask?.cancel()
        signInToastVisible = true
        errorView.isHidden = true
        signInToast.update(
            message: "Signed in successfully",
            announce: true,
            style: .success
        )
        signInToast.place(in: root.bounds)
        signInToastTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.dismissSignInToast()
        }
    }

    /// Restores normal error presentation after the success notice closes or expires.
    private func dismissSignInToast() {
        guard signInToastVisible else { return }
        signInToastTask?.cancel()
        signInToastTask = nil
        signInToastVisible = false
        signInToast.update(
            message: nil,
            announce: false
        )
        errorView.isHidden = loginPage != nil || generationRepo.errorMessage == nil
    }

    /// Installs persistent page relationships while keeping both SDK previews mounted.
    private func configureLayout() {
        scroll.snp.makeConstraints { make in make.edges.equalToSuperview() }
        document.snp.makeConstraints { make in
            // Viewport-derived heights follow resizing instead of becoming a window minimum.
            make.leading.top.equalTo(scroll.contentView)
            make.width.equalTo(scroll.contentView)
            make.height.equalTo(0).priority(490)
        }
        header.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(28)
            make.top.equalToSuperview().offset(16)
            make.height.equalTo(0).priority(490)
        }
        landing.snp.makeConstraints { make in
            make.leading.trailing.equalTo(header)
            make.top.equalTo(header.snp.bottom).offset(30)
            make.height.equalTo(0).priority(490)
        }
        workspace.snp.makeConstraints { make in
            make.leading.trailing.equalTo(header)
            make.top.equalTo(header.snp.bottom)
            make.height.equalTo(0).priority(490)
        }
        footer.snp.makeConstraints { make in
            make.leading.trailing.equalTo(header)
            make.bottom.equalToSuperview().inset(48)
            make.height.equalTo(80)
        }
        logo.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.top.equalToSuperview().offset(8)
            make.height.equalTo(34)
            make.width.equalTo(logo.snp.height).multipliedBy(552.0 / 172)
        }
        userView.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.centerY.equalTo(logo)
            make.width.equalTo(userView.preferredWidth(controlHeight: 36))
            make.height.equalTo(36)
        }
        homeControls.snp.makeConstraints { make in
            make.trailing.equalTo(userView.snp.leading).offset(-12)
            make.centerY.equalTo(logo)
            make.width.equalTo(cameraControls.preferredWidth)
            make.height.equalTo(36)
        }
        cameraControls.snp.makeConstraints { make in make.edges.equalToSuperview() }
        toolbar.snp.makeConstraints { make in
            make.trailing.equalTo(userView.snp.leading).offset(-20)
            make.centerY.equalTo(logo)
            make.width.equalTo(toolbar.preferredWidth)
            make.height.equalTo(36)
        }
    }

    /// Supplies current viewport dimensions before AppKit resolves the persistent child constraints.
    override func viewWillLayout() {
        super.viewWillLayout()
        let width = root.bounds.width
        let height = root.bounds.height
        guard width > 0, height > 0 else { return }
        let active = generationRepo.sessionActive
        let controlHeight = min(48, max(35, width * 0.0055 + 26))
        let cameraWidth = cameraControls.preferredWidth
        let userWidth = userView.preferredWidth(controlHeight: controlHeight)
        let signature =
            "\(width)|\(height)|\(active)|\(cameraWidth)|\(userWidth)|\(toolbar.preferredWidth)|\(displayedError ?? "")"
        guard signature != layoutSignature else { return }
        layoutSignature = signature
        let contentWidth = max(0, width - 56)
        landing.viewportWidth = width
        let landingHeight = landing.preferredHeight(contentWidth: contentWidth)
        let workspaceHeight = workspace.preferredHeight(contentWidth: contentWidth)
        let logoHeight = min(52, max(34, width * 0.008 + 24))
        let headerHeight = max(logoHeight, active ? 36 : controlHeight) + 32
        let minimumHeight =
            active
            ? 16 + headerHeight + workspaceHeight + 48
            : 16 + headerHeight + 30 + landingHeight + 30 + 80 + 48
        let documentHeight = max(height, minimumHeight)
        let surplus = max(0, documentHeight - minimumHeight)
        document.snp.updateConstraints { make in make.height.equalTo(documentHeight).priority(490) }
        header.snp.updateConstraints { make in
            make.top.equalToSuperview().offset(16 + (active ? surplus / 2 : 0))
            make.height.equalTo(headerHeight).priority(490)
        }
        landing.snp.updateConstraints { make in
            make.top.equalTo(header.snp.bottom).offset(30 + surplus / 2)
            make.height.equalTo(landingHeight).priority(490)
        }
        workspace.snp.updateConstraints { make in make.height.equalTo(workspaceHeight).priority(490) }
        logo.snp.updateConstraints { make in make.height.equalTo(logoHeight) }
        userView.snp.updateConstraints { make in
            make.width.equalTo(userWidth)
            make.height.equalTo(controlHeight)
        }
        homeControls.snp.updateConstraints { make in
            make.width.equalTo(cameraWidth)
            make.height.equalTo(controlHeight)
        }
        toolbar.snp.updateConstraints { make in make.width.equalTo(toolbar.preferredWidth) }
        errorView.place(in: root.bounds)
        if signInToastVisible { signInToast.place(in: root.bounds) }
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
