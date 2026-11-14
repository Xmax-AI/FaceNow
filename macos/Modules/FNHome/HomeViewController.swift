//
//  HomeViewController.swift
//  FaceNow
//

import Factory
import AppKit
import Combine
import SnapKit
import XmaxSDK

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

    /// Presents login form failures in the shared toast without changing the form layout.
    private var loginRequestError: String?

    /// Owns the initial saved-session validation.
    private var accountRestore: Task<Void, Never>?

    /// Refreshes credits while a validated account is displayed in the home header.
    private var accountRefresh: Task<Void, Never>?

    /// The generation lifecycle owner, created with the same user settings as the editor.
    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    /// The extension owner refreshed when the application becomes active.
    @Injected(\.virtualCameraRepo) var virtualCameraRepo: VirtualCameraRepository

    /// Allows application installation only after capture, generation, and native camera work stop.
    var canInstallApplicationUpdate: Bool {
        !isShuttingDown && !generationRepo.settingsLocked && !generationRepo.isClosing
            && rechargeDialog == nil && userRepo.rechargeNoticeID == nil
            && !virtualCameraRepo.isBusy && !virtualCameraRepo.hasPendingSystemRequest
            && !virtualCameraRepo.isRequestingCameraAccess
            && virtualCameraRepo.operation == nil && cameraStartTask == nil && cameraNoticeTask == nil
    }

    /// Lets application composition resume a requested update after committed state changes.
    var onUpdateInstallationAvailabilityChanged: (() -> Void)?

    /// The preparation presentation model shared with the persistent home reminder.
    private lazy var onboardingModel: OnboardingFlowViewModel = {
        let viewModel = OnboardingFlowViewModel()
        return viewModel
    }()

    /// Maps camera readiness to notice content and validates each typed user command.
    private lazy var cameraStatusModel: CameraStatusViewModel = {
        let model = CameraStatusViewModel()
        return model
    }()

    /// Owns only the initiating UI task; the repository retains native device workflows.
    private var cameraNoticeTask: Task<Void, Never>?

    /// The currently mounted modal preparation guide.
    private var onboardingPage: OnboardingViewController?

    /// The company and model information modal, mutually exclusive with onboarding.
    private var aboutPage: AboutViewController?

    /// Retains the centered live translation configuration while the workspace is active.
    private var translationDialog: GenerationTranslationDialogView?

    /// Retains one credit overlay and the account notice it acknowledges.
    private var rechargeDialog: (id: UUID, view: RechargeDialogView)?

    /// Restores the covered page's focus without repeating its presentation or business actions.
    private weak var rechargePreviousResponder: NSResponder?

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

    /// Displays the supplied FaceNow brand artwork in the product header.
    private lazy var logoIcon: NSImageView = {
        let view = NSImageView()
        view.image = NSImage(named: "FaceNowBrandMark")
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityElement(false)
        return view
    }()

    /// Names the product consistently in both regional editions.
    private lazy var logoTitle: NSTextField = {
        let view = NSTextField(labelWithString: "FaceNow")
        view.font = .systemFont(ofSize: 24, weight: .semibold)
        view.textColor = Palette.text
        return view
    }()

    /// Aligns the FaceNow brand artwork and wordmark on the shared header centerline.
    private lazy var logo: NSStackView = {
        let view = NSStackView(views: [logoIcon, logoTitle])
        view.orientation = .horizontal
        view.alignment = .centerY
        view.spacing = 8
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
        view.onOpenCameraSettings = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isShuttingDown, !self.viewModel.needsLogin else { return }
                await self.routeCameraNoticeAction(.openSettings(.cameraExtensions))
            }
        }
        view.onShowMicrophoneSetup = { [weak self] in self?.microphoneSetup.presentSetup() }
        return view
    }()

    /// Presents explicit audio-driver actions from the virtual-device popover.
    private lazy var microphoneSetup: VirtualMicrophoneSetupViewController = {
        let controller = VirtualMicrophoneSetupViewController()
        return controller
    }()

    /// The credential editor owned by FNUser.
    private lazy var userView: UserAccountToolbarView = {
        let view = UserAccountToolbarView()
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
        view.onToggleBeauty = { [weak self] in self?.workspace.toggleBeauty() }
        view.onConfigureTranslation = { [weak self] in self?.showTranslationDialog() }
        return view
    }()

    /// The initial camera-start experience owned by FNOnboarding.
    private lazy var landing: OnboardingLandingView = {
        let view = OnboardingLandingView()
        view.onStart = { [weak self] preset, reference in
            self?.startCamera(
                preset: preset,
                reference: reference
            )
        }
        view.onReferenceImportError = { [weak self] message in self?.generationRepo.showSetupError(message) }
        view.onShowCameraSetup = { [weak self] in self?.showOnboarding(at: .camera) }
        view.onShowMicrophoneSetup = { [weak self] in self?.showOnboarding(at: .microphone) }
        view.onCameraAction = { [weak self] action in self?.performCameraNoticeAction(action) }
        return view
    }()

    /// The persistent generation workspace, mounted before camera readiness.
    private lazy var workspace: GenerationWorkspaceView = {
        let view = GenerationWorkspaceView()
        view.onShowMicrophoneSetup = { [weak self] in self?.showOnboarding(at: .microphone) }
        return view
    }()

    /// The home-page product links and follow popover.
    private lazy var footer: HomeFooterView = {
        let view = HomeFooterView()
        view.onShowAbout = { [weak self] in self?.showAbout() }
        return view
    }()

    /// The selectable error notification overlaid on the window content.
    private lazy var errorView: ToastView = {
        let view = ToastView()
        view.onDismiss = { [weak self] in self?.dismissCurrentError() }
        return view
    }()

    /// The success notification retained above the newly authenticated home page.
    private lazy var signInToast: ToastView = {
        let view = ToastView()
        view.onDismiss = { [weak self] in self?.dismissSignInToast() }
        return view
    }()

    /// Whether the success toast temporarily owns the notification position.
    private var signInToastVisible = false

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

    /// The warning used for the last measured landing-page layout.
    private var displayedCameraWarning: CameraNoticePresentation?

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
        [
            logo, homeControls, toolbar.statisticsControl, toolbar.interpolationControl, toolbar.beautyControl,
            toolbar, userView,
        ].forEach(
            header.addSubview
        )
        if GenerationRepository.isLiveTranslationAvailable { header.addSubview(toolbar.translationControl) }
        homeControls.addSubview(cameraControls)
        configureLayout()

        userRepo.objectWillChange.sink { [weak self] in self?.scheduleRender() }.store(in: &observations)
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
        NotificationCenter.default.publisher(for: NSWindow.didEndSheetNotification)
            .sink { [weak self] _ in self?.scheduleRender() }
            .store(in: &observations)
        render()
        accountRestore = Task { [weak self] in await self?.userRepo.restore() }
    }

    /// Starts the existing status refresh cadence after the page is attached.
    override func viewDidAppear() {
        super.viewDidAppear()
        synchronizeCameraSelection()
        synchronizeOnboarding()
        updateRechargeDialog()
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

    /// The pending explicit startup of generation capture.
    private var cameraStartTask: Task<Void, Never>?

    /// Stops view work before awaiting generation and virtual-output cleanup.
    func shutdown() async {
        isShuttingDown = true
        dismissTranslationDialog()
        dismissRechargeDialog()
        cameraNoticeTask?.cancel()
        cameraNoticeTask = nil
        virtualCameraRepo.cancelPendingOperations()
        cameraStartTask?.cancel()
        dismissOnboarding(animated: false)
        dismissAbout(animated: false)
        accountRestore?.cancel()
        accountRestore = nil
        accountRefresh?.cancel()
        accountRefresh = nil
        userRepo.cancelPendingOperations()
        loginPage?.shutdown()
        observations.removeAll()
        ticker?.cancel()
        ticker = nil
        signInToast.shutdown()
        errorView.shutdown()
        landing.closeCameraPicker()
        cameraControls.closePopover()
        userView.shutdown()
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

    /// Checks permission and the cached balance without requesting credits during camera startup.
    private func startCamera(
        preset: RealtimeCameraPreset,
        reference: GenerationReference
    ) {
        guard loginPage == nil, aboutPage == nil, cameraStartTask == nil, cameraNoticeTask == nil, !isShuttingDown
        else { return }
        virtualCameraRepo.synchronizeReadiness()
        guard viewModel.canStart else {
            generationRepo.showSetupError(viewModel.startUnavailableMessage)
            return
        }
        guard !userRepo.hasInsufficientCredits else {
            userRepo.requestRechargeNotice()
            return
        }
        let requestedAt = DispatchTime.now().uptimeNanoseconds
        cameraStartTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.cameraStartTask = nil
                self.scheduleRender()
            }
            guard !Task.isCancelled, !self.isShuttingDown, !self.viewModel.needsLogin,
                self.onboardingPage == nil, self.aboutPage == nil
            else { return }
            await self.viewModel.startCamera(
                preset: preset,
                reference: reference,
                requestedAt: requestedAt
            )
        }
        scheduleRender()
    }

    /// Populates the authenticated home's selector as soon as camera permission allows enumeration.
    private func synchronizeCameraSelection() {
        guard !isShuttingDown, !viewModel.needsLogin, view.window != nil,
            virtualCameraRepo.canStartSession, !generationRepo.settingsLocked
        else { return }
        virtualCameraRepo.prepareCameraInputs()
        generationRepo.refreshCameras()
    }

    /// Applies committed state through each business component without recreating its views.
    private func render() {
        synchronizeCameraSelection()
        onboardingModel.synchronize()
        let active = generationRepo.sessionActive
        let pageChanged = displayedSession != active
        let cameraWarning = cameraStatusModel.presentation
        let cameraWarningChanged = cameraWarning != displayedCameraWarning
        displayedCameraWarning = cameraWarning
        let previousCameraWidth = cameraControls.preferredWidth
        let previousUserWidth = userView.preferredWidth(controlHeight: homeControls.bounds.height)
        userView.showsAvatar = !active
        userView.update()
        toolbar.update()
        landing.update(
            isStarting: viewModel.isStarting || cameraStartTask != nil,
            canStart: viewModel.canStart,
            unavailableMessage: viewModel.startUnavailableMessage
        )
        landing.updatePreparation(presentation: cameraWarning)
        workspace.update(resetReferenceScroll: pageChanged)
        let needsPageLayout =
            pageChanged
            || previousCameraWidth != cameraControls.preferredWidth
            || cameraWarningChanged
            || previousUserWidth != userView.preferredWidth(controlHeight: homeControls.bounds.height)
            || displayedError != currentErrorMessage

        homeControls.isHidden = active
        toolbar.statisticsControl.isHidden = !active
        toolbar.interpolationControl.isHidden = !active
        toolbar.beautyControl.isHidden = !active
        if GenerationRepository.isLiveTranslationAvailable { toolbar.translationControl.isHidden = !active }
        toolbar.isHidden = !active
        landing.isHidden = active
        footer.isHidden = active
        workspace.isHidden = !active
        if pageChanged {
            displayedSession = active
            landing.closeCameraPicker()
            cameraControls.closePopover()
            userView.closePopover()
            footer.closePopover()
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            view.window?.makeFirstResponder(nil)
        }
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
        updateError()
        updateRechargeDialog()
        if active, !generationRepo.isClosing, !viewModel.needsLogin {
            translationDialog?.update()
        } else {
            dismissTranslationDialog()
        }
        onUpdateInstallationAvailabilityChanged?()
    }

    /// Opens live translation configuration without starting or stopping capture.
    private func showTranslationDialog() {
        guard GenerationRepository.isLiveTranslationAvailable, translationDialog == nil,
            generationRepo.sessionActive, !generationRepo.isClosing,
            !isShuttingDown, !viewModel.needsLogin, onboardingPage == nil, aboutPage == nil, rechargeDialog == nil,
            let window = view.window, window.attachedSheet == nil
        else { return }
        userView.closePopover()
        let dialog = GenerationTranslationDialogView(repository: generationRepo)
        dialog.onClose = { [weak self] in self?.dismissTranslationDialog(animated: true) }
        dialog.onShowMicrophoneSetup = { [weak self] in self?.showOnboarding(at: .microphone) }
        translationDialog = dialog
        root.addSubview(dialog)
        dialog.snp.makeConstraints { make in make.edges.equalToSuperview() }
        root.layoutSubtreeIfNeeded()
        dialog.present()
    }

    /// Removes configuration after user dismissal or immediately when the session changes.
    private func dismissTranslationDialog(
        animated: Bool = false
    ) {
        guard let dialog = translationDialog else { return }
        // Capture the input before the animated completion runs outside the original event.
        let eventType = NSApp.currentEvent?.type
        let restoresToolbarFocus = eventType != .leftMouseDown && eventType != .leftMouseUp
        dialog.dismiss(animated: animated) { [weak self, weak dialog] in
            guard let self, let dialog, self.translationDialog === dialog else { return }
            self.translationDialog = nil
            dialog.shutdown()
            dialog.removeFromSuperview()
            if animated, self.generationRepo.sessionActive {
                self.view.window?.makeFirstResponder(restoresToolbarFocus ? self.toolbar.translationControl : nil)
            }
        }
    }

    /// Presents the same centered credit dialog for rejected startup and exhausted generation.
    private func updateRechargeDialog() {
        guard !isShuttingDown, !viewModel.needsLogin, let noticeID = userRepo.rechargeNoticeID else {
            dismissRechargeDialog()
            return
        }
        if let presented = rechargeDialog {
            if presented.id == noticeID {
                let responder = view.window?.firstResponder as? NSView
                if responder?.isDescendant(of: presented.view) != true { presented.view.focus() }
                return
            }
            dismissRechargeDialog()
        }
        guard let window = view.window, window.isVisible, window.attachedSheet == nil else { return }
        dismissTranslationDialog()
        landing.closeCameraPicker()
        cameraControls.closePopover()
        userView.closePopover()
        footer.closePopover()
        landing.setServiceNoticeInteractionEnabled(false)
        dismissSignInToast()
        let dialog = RechargeDialogView()
        dialog.onRecharge = { [weak self] in
            self?.resolveRechargeDialog(
                id: noticeID,
                opensCredits: true
            )
        }
        dialog.onDismiss = { [weak self] in
            self?.resolveRechargeDialog(
                id: noticeID,
                opensCredits: false
            )
        }
        rechargePreviousResponder = window.firstResponder
        rechargeDialog = (noticeID, dialog)
        root.addSubview(dialog)
        dialog.snp.makeConstraints { make in make.edges.equalToSuperview() }
        root.layoutSubtreeIfNeeded()
        dialog.present()
    }

    /// Acknowledges only the current notice and opens the regional credit page after an explicit choice.
    private func resolveRechargeDialog(
        id: UUID,
        opensCredits: Bool
    ) {
        guard let presented = rechargeDialog, presented.id == id, !presented.view.isDismissing else { return }
        let isCurrent = userRepo.rechargeNoticeID == id
        dismissRechargeDialog(animated: true)
        if isCurrent, opensCredits, !isShuttingDown, !viewModel.needsLogin {
            NSWorkspace.shared.open(userRepo.creditsURL)
        }
    }

    /// Removes stale overlays immediately on lifecycle changes or after the user's dismissal fade.
    private func dismissRechargeDialog(
        animated: Bool = false
    ) {
        guard let presented = rechargeDialog else { return }
        let noticeID = presented.id
        presented.view.dismiss(animated: animated) { [weak self, weak dialog = presented.view] in
            guard let self, let dialog, self.rechargeDialog?.view === dialog else { return }
            dialog.shutdown()
            dialog.removeFromSuperview()
            self.rechargeDialog = nil
            self.userRepo.dismissRechargeNotice(id: noticeID)
            self.landing.setServiceNoticeInteractionEnabled(self.onboardingPage == nil && self.aboutPage == nil)
            if !self.isShuttingDown, !self.viewModel.needsLogin,
                let previous = self.rechargePreviousResponder as? NSView,
                previous.window === self.view.window, !previous.isHiddenOrHasHiddenAncestor
            {
                self.view.window?.makeFirstResponder(previous)
            } else {
                self.view.window?.makeFirstResponder(nil)
            }
            self.rechargePreviousResponder = nil
            self.scheduleRender()
        }
    }

    /// Schedules first presentation or a pending relaunch continuation after verified home readiness.
    private func synchronizeOnboarding() {
        guard !isShuttingDown else { return }
        if viewModel.needsLogin {
            onboardingAutoPresented = false
            dismissOnboarding(animated: false)
            return
        }
        let resumeStep = onboardingModel.onboardingRepo.resumeStepAfterRelaunch
        guard userRepo.hasVerifiedSession, view.window != nil, !generationRepo.sessionActive,
            !generationRepo.settingsLocked, aboutPage == nil, onboardingPage == nil,
            rechargeDialog == nil, userRepo.rechargeNoticeID == nil,
            onboardingPresentationTask == nil, !onboardingAutoPresented || resumeStep != nil
        else { return }
        if resumeStep != nil, case .checking = virtualCameraRepo.readiness { return }
        onboardingAutoPresented = true
        guard resumeStep != nil || !onboardingModel.onboardingRepo.hasShownGuide else { return }
        onboardingPresentationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.onboardingPresentationTask = nil
            guard !self.isShuttingDown, self.userRepo.hasVerifiedSession, !self.viewModel.needsLogin,
                self.loginPage == nil, self.view.window != nil, !self.generationRepo.settingsLocked,
                self.onboardingPage == nil, self.aboutPage == nil,
                self.rechargeDialog == nil, self.userRepo.rechargeNoticeID == nil
            else { return }
            let resumeStep = self.onboardingModel.onboardingRepo.resumeStepAfterRelaunch
            guard resumeStep != nil || !self.onboardingModel.onboardingRepo.hasShownGuide else { return }
            if resumeStep != nil, case .checking = self.virtualCameraRepo.readiness { return }
            self.showOnboarding(
                at: resumeStep,
                dismissesOnBackdropClick: false
            )
        }
    }

    /// Opens guidance from the banner without executing device commands outside the modal.
    private func performCameraNoticeAction(
        _ action: CameraNoticeAction
    ) {
        guard case .showHelp = action else { return }
        guard !isShuttingDown, !viewModel.needsLogin,
            cameraNoticeTask == nil, onboardingPage == nil, aboutPage == nil
        else { return }
        onboardingPresentationTask?.cancel()
        onboardingPresentationTask = nil
        onboardingAutoPresented = true
        cameraNoticeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.cameraNoticeTask = nil }
            let navigation = self.cameraStatusModel.presentation?.action ?? action
            guard !Task.isCancelled, !self.isShuttingDown, !self.viewModel.needsLogin else { return }
            await self.routeCameraNoticeAction(navigation)
            self.scheduleRender()
        }
    }

    /// Opens microphone privacy settings after the guide's explicit settings action.
    private func openMicrophoneSettings() {
        guard !isShuttingDown, !viewModel.needsLogin else { return }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"),
            NSWorkspace.shared.open(url)
        else {
            generationRepo.showSetupError(GenerationStrings.microphonePermissionRequired)
            return
        }
    }

    /// Keeps native navigation and application cleanup outside the notice view and device model.
    private func routeCameraNoticeAction(
        _ action: CameraNoticeAction
    ) async {
        switch action {
        case .openSettings(.cameraPrivacy):
            onboardingModel.openCameraSettings()
        case .openSettings(.cameraExtensions):
            virtualCameraRepo.recordRecoveryNavigation(relaunch: false)
            virtualCameraRepo.openSettings()
        case .chooseCamera:
            landing.showCameraPicker()
        case .showHelp(.restrictedCameraAccess), .showHelp(.cameraAccess):
            showOnboarding(at: .camera)
        case .showHelp(.virtualCamera):
            showOnboarding(at: .virtualCamera)
        case .revealApplication:
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        case .restartApplication:
            virtualCameraRepo.recordRecoveryNavigation(relaunch: true)
            await generationRepo.close()
            guard !Task.isCancelled, !isShuttingDown, !viewModel.needsLogin else { return }
            do {
                onboardingModel.onboardingRepo.prepareForRelaunch()
                try await ApplicationLifecycleActions.launchReplacement()
                NSApplication.shared.terminate(nil)
            } catch {
                generationRepo.showSetupError(HomeStrings.homeCouldnTRestartFaceNowQuitAndReopenTheApp)
            }
        case .copyErrorDetails:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(virtualCameraRepo.setupDiagnostic, forType: .string)
        case .requestCameraAccess, .installVirtualCamera, .reinstallVirtualCamera, .retry, .checkAgain:
            break
        }
    }

    /// Opens static product information without starting capture or sharing preparation progress.
    private func showAbout() {
        guard !isShuttingDown, !viewModel.needsLogin, !generationRepo.sessionActive,
            cameraStartTask == nil, cameraNoticeTask == nil, view.window != nil
        else { return }
        onboardingPresentationTask?.cancel()
        onboardingPresentationTask = nil
        onboardingAutoPresented = true
        dismissOnboarding(animated: false)
        landing.setServiceNoticeInteractionEnabled(false)
        landing.closeCameraPicker()
        cameraControls.closePopover()
        userView.closePopover()
        footer.closePopover()
        if let page = aboutPage {
            page.present()
            return
        }
        let page = AboutViewController()
        page.onDismiss = { [weak self] in self?.dismissAbout() }
        aboutPage = page
        addChild(page)
        root.addSubview(page.view)
        page.view.snp.makeConstraints { make in make.edges.equalToSuperview() }
        root.layoutSubtreeIfNeeded()
        page.present()
    }

    /// Removes About Us after its shared modal exit or immediately for account and app lifecycle changes.
    private func dismissAbout(
        animated: Bool = true
    ) {
        guard let page = aboutPage else { return }
        page.dismiss(animated: animated) { [weak self, weak page] in
            guard let self, let page, self.aboutPage === page else { return }
            page.shutdown()
            page.view.removeFromSuperview()
            page.removeFromParent()
            self.aboutPage = nil
            self.landing.setServiceNoticeInteractionEnabled(self.onboardingPage == nil)
            self.view.window?.makeFirstResponder(nil)
        }
    }

    /// Mounts the guide at the relevant preparation step above the existing home content.
    private func showOnboarding(
        at step: OnboardingRepository.Step? = nil,
        dismissesOnBackdropClick: Bool = true
    ) {
        guard !isShuttingDown, !viewModel.needsLogin, view.window != nil else { return }
        dismissTranslationDialog()
        dismissAbout(animated: false)
        onboardingPresentationTask?.cancel()
        onboardingPresentationTask = nil
        onboardingAutoPresented = true
        landing.setServiceNoticeInteractionEnabled(false)
        landing.closeCameraPicker()
        cameraControls.closePopover()
        userView.closePopover()
        footer.closePopover()
        onboardingModel.refresh()
        onboardingModel.onboardingRepo.begin(
            at: step
        )
        if let page = onboardingPage {
            page.dismissesOnBackdropClick = dismissesOnBackdropClick
            page.present()
            return
        }
        let page = OnboardingViewController(
            viewModel: onboardingModel,
            dismissesOnBackdropClick: dismissesOnBackdropClick
        )
        page.onDismiss = { [weak self] in self?.dismissOnboarding() }
        page.onMicrophoneSettings = { [weak self] in self?.openMicrophoneSettings() }
        page.onCameraNavigation = { [weak self] action in
            guard let self, !Task.isCancelled, !self.isShuttingDown, !self.viewModel.needsLogin else { return }
            await self.routeCameraNoticeAction(action)
        }
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
            self.landing.setServiceNoticeInteractionEnabled(true)
            self.view.window?.makeFirstResponder(nil)
        }
    }

    /// Starts a bounded refresh cadence and stops it when the account leaves the home page.
    private func synchronizeAccountRefresh() {
        guard userRepo.hasVerifiedSession else {
            accountRefresh?.cancel()
            accountRefresh = nil
            return
        }
        guard accountRefresh == nil else { return }
        accountRefresh = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.isShuttingDown, self.userRepo.hasVerifiedSession else { return }
                await self.userRepo.refreshCredits()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }

    /// Shows a full native login page while preserving mounted generation preview bindings.
    private func synchronizeLoginPage() {
        guard isViewLoaded, !isShuttingDown else { return }
        let needsLogin = viewModel.needsLogin
        if needsLogin, loginPage == nil {
            dismissAbout(animated: false)
            cameraNoticeTask?.cancel()
            dismissSignInToast()
            userView.closePopover()
            landing.closeCameraPicker()
            landing.resetReferenceSelection()
            cameraControls.closePopover()
            let form = UserLoginFormView()
            form.onRequestError = { [weak self] message in
                guard let self, !self.isShuttingDown else { return }
                self.loginRequestError = message
                if message != nil { self.userRepo.dismissSessionNotice() }
                self.scheduleRender()
            }
            let page = UserLoginViewController(formView: form)
            form.presenter = page
            loginPage = page
            addChild(page)
            root.addSubview(page.view)
            root.addSubview(
                errorView,
                positioned: .above,
                relativeTo: page.view
            )
            page.view.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
            scroll.isHidden = true
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
            loginRequestError = nil
            scroll.isHidden = false
            if root.window != nil {
                root.layoutSubtreeIfNeeded()
                animateEntry(document)
            }
        }
    }

    /// Stops billable generation and virtual output before invalidating account credentials.
    private func signOut() {
        dismissAbout(animated: false)
        dismissOnboarding()
        cameraStartTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            await self.viewModel.signOut()
        }
    }

    /// Gives authentication notices precedence and keeps unrelated generation errors off the login page.
    private var currentErrorMessage: String? {
        userRepo.sessionNotice ?? (viewModel.needsLogin ? loginRequestError : generationRepo.errorMessage)
    }

    /// Clears the current form notice or dismisses its owning repository's error.
    private func dismissCurrentError() {
        if userRepo.sessionNotice != nil {
            userRepo.dismissSessionNotice()
        } else if viewModel.needsLogin, loginRequestError != nil {
            loginRequestError = nil
            scheduleRender()
        } else {
            generationRepo.dismissError()
        }
    }

    /// Announces each new error once and retains the existing auto-dismiss interval.
    private func updateError() {
        let message = currentErrorMessage
        let changed = displayedError != message
        if changed, message != nil { dismissSignInToast() }
        errorView.update(
            message: signInToastVisible ? nil : message,
            announce: changed && !signInToastVisible
        )
        guard changed else { return }
        displayedError = message
    }

    /// Shows one success toast only for an explicit, validated login event.
    private func showSignInToast() {
        guard !isShuttingDown, userRepo.canAccessHome else { return }
        synchronizeLoginPage()
        signInToastVisible = true
        errorView.update(
            message: nil,
            announce: false
        )
        signInToast.update(
            message: HomeStrings.homeSignedInSuccessfully,
            announce: true,
            style: .success
        )
        signInToast.place(in: root.bounds)
    }

    /// Restores normal error presentation after the success notice closes or expires.
    private func dismissSignInToast() {
        guard signInToastVisible else { return }
        signInToastVisible = false
        signInToast.update(
            message: nil,
            announce: false
        )
        errorView.update(
            message: currentErrorMessage,
            announce: false
        )
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
            make.leading.equalTo(document.snp.leading).offset(24)
            make.top.equalToSuperview().offset(8)
            make.height.equalTo(40)
        }
        logoIcon.snp.makeConstraints { make in
            make.width.height.equalTo(logo.snp.height)
        }
        userView.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.centerY.equalTo(logo)
            make.width.equalTo(userView.preferredWidth(controlHeight: 36))
            make.height.equalTo(36)
        }
        homeControls.snp.makeConstraints { make in
            make.trailing.equalTo(userView.snp.leading).offset(-ToolbarControlMetrics.spacing)
            make.centerY.equalTo(logo)
            make.width.equalTo(cameraControls.preferredWidth)
            make.height.equalTo(36)
        }
        cameraControls.snp.makeConstraints { make in make.edges.equalToSuperview() }
        toolbar.statisticsControl.snp.makeConstraints { make in
            make.trailing.equalTo(toolbar.interpolationControl.snp.leading).offset(-ToolbarControlMetrics.spacing)
            make.centerY.equalTo(logo)
            make.height.equalTo(userView)
        }
        toolbar.interpolationControl.snp.makeConstraints { make in
            make.trailing.equalTo(toolbar.beautyControl.snp.leading).offset(-ToolbarControlMetrics.spacing)
            make.centerY.equalTo(logo)
            make.height.equalTo(userView)
            make.width.equalTo(toolbar.interpolationControl.preferredWidth)
        }
        let controlAfterBeauty = GenerationRepository.isLiveTranslationAvailable ? toolbar.translationControl : userView
        toolbar.beautyControl.snp.makeConstraints { make in
            make.trailing.equalTo(controlAfterBeauty.snp.leading).offset(-ToolbarControlMetrics.spacing)
            make.centerY.equalTo(logo)
            make.height.equalTo(userView)
            make.width.equalTo(toolbar.beautyControl.preferredWidth)
        }
        if GenerationRepository.isLiveTranslationAvailable {
            toolbar.translationControl.snp.makeConstraints { make in
                make.trailing.equalTo(userView.snp.leading).offset(-ToolbarControlMetrics.spacing)
                make.centerY.equalTo(logo)
                make.height.equalTo(userView)
                make.width.equalTo(toolbar.translationControl.preferredWidth)
            }
        }
        toolbar.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.centerY.equalTo(logo)
            make.width.equalTo(toolbar.preferredWidth)
            make.height.equalTo(userView)
        }
    }

    /// Supplies current viewport dimensions before AppKit resolves the persistent child constraints.
    override func viewWillLayout() {
        super.viewWillLayout()
        let width = root.bounds.width
        let height = root.bounds.height
        guard width > 0, height > 0 else { return }
        let active = generationRepo.sessionActive
        let controlHeight = ToolbarControlMetrics.compactHeight
        let cameraWidth = cameraControls.preferredWidth
        let userWidth = userView.preferredWidth(controlHeight: controlHeight)
        let toolbarWidth = toolbar.preferredWidth
        let interpolationWidth = toolbar.interpolationControl.preferredWidth
        let beautyWidth = toolbar.beautyControl.preferredWidth
        let translationWidth = GenerationRepository.isLiveTranslationAvailable ? toolbar.translationControl.preferredWidth : nil
        let signature =
            "\(width)|\(height)|\(active)|\(cameraWidth)|\(userWidth)|\(toolbarWidth)|\(interpolationWidth)|\(beautyWidth)|\(translationWidth ?? 0)|\(displayedError ?? "")|\(displayedCameraWarning?.message ?? "")|\(displayedCameraWarning?.buttonTitle ?? "")"
        guard signature != layoutSignature else { return }
        layoutSignature = signature
        let contentWidth = max(0, width - 56)
        landing.viewportWidth = width
        let landingHeight = landing.preferredHeight(contentWidth: contentWidth)
        let workspaceHeight = workspace.preferredHeight(contentWidth: contentWidth)
        let wordmarkHeight = min(52, max(34, width * 0.008 + 24))
        let logoHeight = wordmarkHeight + 6
        let headerHeight = max(logoHeight, controlHeight) + 32
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
        logoTitle.font = .systemFont(ofSize: wordmarkHeight * 0.7, weight: .semibold)
        userView.snp.updateConstraints { make in
            make.trailing.equalToSuperview().offset(active ? -(toolbarWidth + ToolbarControlMetrics.spacing) : 0)
            make.width.equalTo(userWidth)
            make.height.equalTo(controlHeight)
        }
        homeControls.snp.updateConstraints { make in
            make.width.equalTo(cameraWidth)
            make.height.equalTo(controlHeight)
        }
        toolbar.snp.updateConstraints { make in make.width.equalTo(toolbarWidth) }
        toolbar.interpolationControl.snp.updateConstraints { make in make.width.equalTo(interpolationWidth) }
        toolbar.beautyControl.snp.updateConstraints { make in make.width.equalTo(beautyWidth) }
        if let translationWidth {
            toolbar.translationControl.snp.updateConstraints { make in make.width.equalTo(translationWidth) }
        }
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
