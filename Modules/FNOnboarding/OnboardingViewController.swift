//
//  OnboardingViewController.swift
//  FaceNow
//

import AppKit
import Combine

/// Owns the modal guide's observations, permission task, and dismissal lifecycle.
@MainActor
final class OnboardingViewController: NSViewController {

    /// The home-owned presentation model sharing the application's existing repositories.
    private let viewModel: OnboardingFlowViewModel

    /// Allows a user-opened guide to close from its backdrop while automatic guides retain focus.
    var dismissesOnBackdropClick: Bool {
        didSet {
            if isViewLoaded { guide.dismissesOnBackdropClick = dismissesOnBackdropClick }
        }
    }

    /// Releases the modal after deferral or successful completion.
    var onDismiss: (() -> Void)?

    /// Routes system navigation through the home coordinator while this modal owns cancellation.
    var onCameraNavigation: (@MainActor (CameraNoticeAction) async -> Void)?

    /// Opens microphone privacy settings through the home coordinator.
    var onMicrophoneSettings: (() -> Void)?

    /// The guide content whose callbacks remain bound for its entire presentation.
    private lazy var guide: OnboardingGuideView = {
        let view = OnboardingGuideView()
        view.dismissesOnBackdropClick = dismissesOnBackdropClick
        view.onDismiss = { [weak self] in self?.viewModel.onboardingRepo.dismiss() }
        view.onPrevious = { [weak self] in self?.viewModel.onboardingRepo.previous() }
        view.onPrimary = { [weak self] in self?.performPrimaryAction() }
        view.onSkipAudio = { [weak self] in self?.performPrimaryAction(skippingAudio: true) }
        return view
    }()

    /// The current explicit permission action, cancelled when the guide leaves the window.
    private var actionTask: Task<Void, Never>?

    /// Prevents a cancelled action from clearing a task started after the guide is reopened.
    private var actionID: UUID?

    /// Retains the modal until its exit animation finishes and cancels removal when reopened.
    private var dismissalTask: Task<Void, Never>?

    /// Suppresses state refreshes and repeated dismissals while the modal is leaving.
    private var isDismissing = false

    /// The state and application-focus subscriptions removed with the guide.
    private var observations: Set<AnyCancellable> = []

    /// Coalesces pre-assignment Combine notifications before reading current state.
    private var renderScheduled = false

    /// Rejects already-enqueued renders after the controller is removed.
    private var isStopped = false

    /// Uses the same presentation model as the persistent home reminder.
    init(
        viewModel: OnboardingFlowViewModel,
        dismissesOnBackdropClick: Bool = true
    ) {
        self.viewModel = viewModel
        self.dismissesOnBackdropClick = dismissesOnBackdropClick
        super.init(nibName: nil, bundle: nil)
    }

    /// Storyboard decoding is unsupported for this programmatic controller.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Binds system and repository changes without starting capture or generation.
    override func loadView() {
        view = guide
        viewModel.virtualMicrophoneRepo.resetDeviceCheck()
        viewModel.objectWillChange.sink { [weak self] in self?.scheduleRender() }.store(in: &observations)
        viewModel.onboardingRepo.objectWillChange.sink { [weak self] in self?.scheduleRender() }.store(
            in: &observations
        )
        viewModel.virtualCameraRepo.objectWillChange.sink { [weak self] in self?.scheduleRender() }.store(
            in: &observations
        )
        viewModel.generationRepo.objectWillChange.sink { [weak self] in self?.scheduleRender() }.store(
            in: &observations
        )
        viewModel.virtualMicrophoneRepo.objectWillChange.sink { [weak self] in self?.scheduleRender() }.store(
            in: &observations
        )
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isStopped, !self.isDismissing else { return }
                    self.viewModel.refresh()
                }
            }.store(in: &observations)
        viewModel.synchronize()
        guide.update(model: viewModel)
    }

    /// Moves keyboard focus inside the modal after it is mounted.
    override func viewDidAppear() {
        super.viewDidAppear()
        focus()
    }

    /// Keeps initial keyboard focus inside the mounted modal's navigation cycle.
    func focus() { guide.focus() }

    /// Enters from below after layout or reverses an unfinished exit from its visible position.
    func present() {
        guard !isStopped, view.window != nil else { return }
        dismissalTask?.cancel()
        dismissalTask = nil
        isDismissing = false
        guide.update(model: viewModel)
        viewModel.onboardingRepo.recordPresentation()
        guide.animatePresentation(visible: true)
        focus()
    }

    /// Defers removal until the fade and downward exit finish, unless lifecycle cleanup is immediate.
    func dismiss(
        animated: Bool,
        completion: @escaping @MainActor () -> Void
    ) {
        guard !isDismissing || !animated else { return }
        dismissalTask?.cancel()
        dismissalTask = nil
        isDismissing = true
        actionTask?.cancel()
        actionTask = nil
        actionID = nil
        guard animated, ControlMotion.isAnimated(in: guide) else {
            completion()
            return
        }
        guide.animatePresentation(visible: false)
        dismissalTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(ControlMotion.duration)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.dismissalTask = nil
            completion()
        }
    }

    /// Cancels view-bound work before the modal is detached or the app terminates.
    func shutdown() {
        isStopped = true
        dismissalTask?.cancel()
        dismissalTask = nil
        actionTask?.cancel()
        actionTask = nil
        actionID = nil
        observations.removeAll()
        viewModel.virtualMicrophoneRepo.resetDeviceCheck()
    }

    /// Owns the explicit action and suppresses navigation after the modal has been dismissed.
    private func performPrimaryAction(
        skippingAudio: Bool = false
    ) {
        guard !isStopped, !isDismissing, actionTask == nil,
            skippingAudio ? viewModel.canSkipAudio : viewModel.primaryPresentation.canPerform
        else { return }
        let actionID = UUID()
        self.actionID = actionID
        actionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.actionID == actionID {
                    self.actionTask = nil
                    self.actionID = nil
                }
            }
            let navigation = await self.viewModel.performPrimaryAction(skippingAudio: skippingAudio)
            guard !Task.isCancelled, !self.isStopped, !self.isDismissing,
                self.viewModel.onboardingRepo.isPresented, let navigation
            else { return }
            switch navigation {
            case .camera(let action): await self.onCameraNavigation?(action)
            case .microphoneSettings: self.onMicrophoneSettings?()
            }
        }
    }

    /// Defers state reads until the published values that triggered them have been committed.
    private func scheduleRender() {
        guard !isStopped, !isDismissing, !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isStopped else { return }
            self.renderScheduled = false
            guard !self.isDismissing else { return }
            self.viewModel.synchronize()
            guard self.viewModel.onboardingRepo.isPresented else {
                self.onDismiss?()
                return
            }
            self.guide.update(model: self.viewModel)
        }
    }
}
