//
//  OnboardingViewController.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import Combine

/// Owns the modal guide's observations, permission task, and dismissal lifecycle.
@MainActor
final class OnboardingViewController: NSViewController {

    /// The home-owned presentation model sharing the application's existing repositories.
    private let viewModel: OnboardingFlowViewModel

    /// Releases the modal after deferral or successful completion.
    var onDismiss: (() -> Void)?

    /// The guide content whose callbacks remain bound for its entire presentation.
    private lazy var guide: OnboardingGuideView = {
        let view = OnboardingGuideView()
        view.onDismiss = { [weak self] in self?.viewModel.onboardingRepo.dismiss() }
        view.onPrevious = { [weak self] in self?.viewModel.onboardingRepo.previous() }
        view.onRefresh = { [weak self] in self?.viewModel.refresh() }
        view.onSettings = { [weak self] in
            guard let self else { return }
            if self.viewModel.onboardingRepo.step == .camera {
                self.viewModel.openCameraSettings()
            } else {
                self.viewModel.virtualCameraRepo.openSettings()
            }
        }
        view.onSelectCamera = { [weak self] id in
            guard let self, !self.viewModel.generationRepo.settingsLocked else { return }
            self.viewModel.generationRepo.cameraID = id
        }
        view.onPrimary = { [weak self] in
            guard let self, !self.isStopped, !self.isDismissing,
                self.actionTask == nil, self.viewModel.primaryEnabled
            else { return }
            self.actionTask = Task { @MainActor [weak self] in
                await self?.viewModel.performPrimaryAction()
                self?.actionTask = nil
            }
        }
        return view
    }()

    /// The current explicit permission action, cancelled when the guide leaves the window.
    private var actionTask: Task<Void, Never>?

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
        viewModel: OnboardingFlowViewModel
    ) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    /// Storyboard decoding is unsupported for this programmatic controller.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Binds system and repository changes without starting capture or generation.
    override func loadView() {
        view = guide
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
        guard !isStopped else { return }
        dismissalTask?.cancel()
        dismissalTask = nil
        isDismissing = false
        guide.update(model: viewModel)
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
        observations.removeAll()
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
