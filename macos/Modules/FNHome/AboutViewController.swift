//
//  AboutViewController.swift
//  FaceNow
//

import AppKit
import Factory

/// Owns the About modal's animated lifecycle and explicit contact navigation.
@MainActor
final class AboutViewController: NSViewController {

    /// Lets home detach this child after its exit animation has completed.
    var onDismiss: (() -> Void)?

    /// Shares the same contact destination as the home footer.
    @Injected(\.homeRepo) private var homeRepo: HomeRepository

    /// Supplies static copy independently of account and camera state.
    private let viewModel = AboutViewModel()

    /// Keeps the content and callbacks stable across presentation and interrupted dismissal.
    private lazy var content: AboutView = {
        let view = AboutView(viewModel: viewModel)
        view.onDismiss = { [weak self] in self?.onDismiss?() }
        view.onContact = { [weak self] in
            guard let self, !self.isStopped, !self.isDismissing else { return }
            NSWorkspace.shared.open(self.homeRepo.contactURL)
        }
        return view
    }()

    /// Defers hierarchy removal until the standard modal motion has completed.
    private var dismissalTask: Task<Void, Never>?

    /// Whether an animated dismissal is in progress.
    private var isDismissing = false

    /// Whether the controller has released its presentation.
    private var isStopped = false

    /// Mounts static content without issuing network, account, or camera work.
    override func loadView() { view = content }

    /// Opens or reverses an unfinished close using the onboarding animation contract.
    func present() {
        guard !isStopped, view.window != nil else { return }
        dismissalTask?.cancel()
        dismissalTask = nil
        isDismissing = false
        content.animatePresentation(visible: true)
        content.focus()
    }

    /// Waits for the shared fade and downward movement before releasing the modal.
    func dismiss(
        animated: Bool,
        completion: @escaping @MainActor () -> Void
    ) {
        guard !isDismissing || !animated else { return }
        dismissalTask?.cancel()
        dismissalTask = nil
        isDismissing = true
        guard animated, ControlMotion.isAnimated(in: content) else {
            completion()
            return
        }
        content.animatePresentation(visible: false)
        dismissalTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(ControlMotion.duration)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.dismissalTask = nil
            completion()
        }
    }

    /// Cancels pending removal during sign-out, shutdown, or immediate page replacement.
    func shutdown() {
        isStopped = true
        dismissalTask?.cancel()
        dismissalTask = nil
    }
}
