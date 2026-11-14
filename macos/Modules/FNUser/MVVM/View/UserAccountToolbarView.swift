//
//  UserAccountToolbarView.swift
//  FaceNow
//

import Factory
import AppKit
import SnapKit

/// Presents the account menu and current credit balance.
@MainActor
final class UserAccountToolbarView: Canvas {

    /// The account and balance shown in the toolbar.
    @Injected(\.userRepo) private var userRepo: UserRepository

    /// Shares the existing policy destinations with the account actions.
    @Injected(\.onboardingRepo) private var onboardingRepo: OnboardingRepository

    /// Formats the avatar and balance without duplicating repository state.
    private lazy var viewModel: UserAccountViewModel = {
        let model = UserAccountViewModel()
        return model
    }()

    /// Requests the full login page from the home coordinator.
    var onSignIn: (() -> Void)?

    /// Requests generation cleanup before signing out.
    var onSignOut: (() -> Void)?

    /// Keeps the avatar on home while allowing a credits-only generation header.
    var showsAvatar = true {
        didSet {
            guard showsAvatar != oldValue else { return }
            button.isHidden = !showsAvatar
            if showsAvatar {
                creditsToTrailing?.deactivate()
                creditsToAvatar?.activate()
            } else {
                creditsToAvatar?.deactivate()
                creditsToTrailing?.activate()
            }
            closePopover()
            needsLayout = true
        }
    }

    /// Leaves the shared gap before the visible avatar.
    private var creditsToAvatar: Constraint?

    /// Lets the credit capsule fill the component when the avatar is hidden.
    private var creditsToTrailing: Constraint?

    /// Opens the existing account menu from a circular text avatar.
    private lazy var button: ToolbarButton = {
        let button = ToolbarButton(
            content: .avatar(
                initials: viewModel.avatarText,
                accessibilityLabel: AccountStrings.accountAccessibility(name: userRepo.displayName)
            ),
            role: .menu,
            tone: .filledAccent
        )
        button.onClick = { [weak self] in self?.showAccount() }
        return button
    }()

    /// Displays server-confirmed credits and opens the platform credit page.
    private lazy var creditsButton: ToolbarButton = {
        let button = ToolbarButton(
            content: .labeled(viewModel.creditsText, icon: .vector(.lightning))
        )
        button.onClick = { [weak self] in
            guard let self else { return }
            self.closePopover()
            NSWorkspace.shared.open(self.userRepo.creditsURL)
        }
        button.onPointerHoverChanged = { [weak self] hovering in
            self?.creditsHoverChanged(hovering)
        }
        return button
    }()

    /// Whether the current transient popover is showing the account card.
    private var showingAccount = false

    /// Distinguishes the credit warning from the account menu.
    private var showingCredits = false

    /// Keeps the warning visible while either hover surface contains the pointer.
    private var creditsButtonHovered = false
    /// Whether the pointer is over the credit warning card.
    private var creditsPopoverHovered = false

    /// Owns the short hover delays and cancels them on page or session changes.
    private var creditsHoverTask: Task<Void, Never>?

    /// Offers recharge through the credit pill's mutually exclusive hover card.
    private lazy var creditsCard: UserCreditsPopoverView = {
        let view = UserCreditsPopoverView()
        view.onRecharge = { [weak self] in
            guard let self else { return }
            self.closePopover()
            NSWorkspace.shared.open(self.userRepo.creditsURL)
        }
        view.onHoverChanged = { [weak self] hovering in
            guard let self, self.showingCredits else { return }
            self.creditsPopoverHovered = hovering
            if hovering {
                self.creditsHoverTask?.cancel()
                self.creditsHoverTask = nil
            } else {
                self.scheduleCreditsDismissal()
            }
        }
        return view
    }()

    /// The persistent account card shares the header's balance and account state.
    private lazy var accountCard: UserAccountPopoverView = {
        let view = UserAccountPopoverView()
        view.onPrivacyPolicy = { [weak self] in
            guard let self else { return }
            self.closePopover()
            NSWorkspace.shared.open(self.onboardingRepo.privacyURL)
        }
        view.onUserAgreement = { [weak self] in
            guard let self else { return }
            self.closePopover()
            NSWorkspace.shared.open(self.onboardingRepo.termsURL)
        }
        view.onRecharge = { [weak self] in
            guard let self else { return }
            self.closePopover()
            NSWorkspace.shared.open(self.userRepo.creditsURL)
        }
        view.onUsage = { [weak self] in
            guard let self else { return }
            self.closePopover()
            NSWorkspace.shared.open(self.userRepo.usageURL)
        }
        view.onSignOut = { [weak self] in self?.signOut() }
        return view
    }()

    /// Owns the active account or credit popover.
    private var popover: NSPopover?

    /// Creates the account and credit controls.
    init() {
        super.init()
        [creditsButton, button].forEach(addSubview)
        button.snp.makeConstraints { make in
            make.trailing.top.bottom.equalToSuperview()
        }
        creditsButton.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            creditsToAvatar =
                make.trailing.equalTo(button.snp.leading).offset(-ToolbarControlMetrics.spacing).constraint
        }
        creditsToTrailing =
            creditsButton.snp.prepareConstraints { make in
                make.trailing.equalToSuperview()
            }.first
        update()
    }

    /// Storyboard decoding is unsupported for this programmatic view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Measures the credit capsule and reserves avatar space only while it is visible.
    func preferredWidth(
        controlHeight: CGFloat
    ) -> CGFloat {
        creditsButton.preferredWidth
            + (showsAvatar ? button.preferredWidth(controlHeight: controlHeight) + ToolbarControlMetrics.spacing : 0)
    }

    /// Refreshes the avatar, credit balance, and any open account menu.
    func update() {
        button.content = .avatar(
            initials: viewModel.avatarText,
            accessibilityLabel: AccountStrings.accountAccessibility(name: userRepo.displayName)
        )
        creditsButton.content = .labeled(viewModel.creditsText, icon: .vector(.lightning))
        creditsButton.tone = viewModel.showsLowCreditsWarning ? .danger : .neutral
        creditsButton.toolTip = viewModel.showsLowCreditsWarning ? nil : viewModel.creditsHelp
        creditsButton.setAccessibilityLabel(AccountStrings.balanceAccessibility(balance: viewModel.creditsText))
        creditsButton.setAccessibilityHelp(viewModel.creditsHelp)
        if !viewModel.showsLowCreditsWarning {
            creditsHoverTask?.cancel()
            creditsHoverTask = nil
            if showingCredits { closePopover() }
        }
        if !userRepo.isSignedIn {
            if showingAccount { closePopover() }
        } else if showingAccount, popover?.isShown == true {
            accountCard.update()
            popover?.contentSize = accountCard.fittingSize
        }
    }

    /// Cancels view-owned work before the application releases account controls.
    func shutdown() {
        closePopover()
    }

    /// Dismisses the popover and cancels hover work.
    func closePopover() {
        creditsHoverTask?.cancel()
        creditsHoverTask = nil
        showingCredits = false
        creditsPopoverHovered = false
        if showingAccount { accountCard.resetMenuHover() }
        showingAccount = false
        popover?.close()
        popover = nil
    }

    /// Cancels hover work when the owning page leaves its native window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            creditsButtonHovered = false
            closePopover()
        }
    }

    /// Prevents a hidden page from leaving an independent popover visible.
    override func viewDidHide() {
        super.viewDidHide()
        creditsButtonHovered = false
        closePopover()
    }

    /// Debounces pointer entry and leaves enough time to move onto the warning card.
    private func creditsHoverChanged(
        _ hovering: Bool
    ) {
        creditsButtonHovered = hovering
        creditsHoverTask?.cancel()
        creditsHoverTask = nil
        guard hovering else {
            scheduleCreditsDismissal()
            return
        }
        guard viewModel.showsLowCreditsWarning else { return }
        guard popover?.isShown != true || showingCredits else { return }
        if showingCredits, popover?.isShown == true { return }
        // End the previous warning lifecycle before starting a new entry delay.
        closePopover()
        creditsHoverTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard let self, self.creditsButtonHovered else { return }
            self.showCreditsWarning()
        }
    }

    /// Dismisses only the warning after the pointer has left both related surfaces.
    private func scheduleCreditsDismissal() {
        guard showingCredits, !creditsButtonHovered, !creditsPopoverHovered else { return }
        creditsHoverTask?.cancel()
        creditsHoverTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self, self.showingCredits,
                !self.creditsButtonHovered, !self.creditsPopoverHovered
            else { return }
            self.closePopover()
        }
    }

    /// Shows the recharge shortcut when the pointer rests on the credit pill.
    private func showCreditsWarning() {
        guard viewModel.showsLowCreditsWarning, window?.isVisible == true,
            !isHiddenOrHasHiddenAncestor,
            popover?.isShown != true || showingCredits
        else { return }
        if showingCredits, popover?.isShown == true { return }
        closePopover()
        let controller = NSViewController()
        controller.view = creditsCard
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = controller
        popover.contentSize = creditsCard.fittingSize
        self.popover = popover
        showingCredits = true
        popover.show(
            relativeTo: creditsButton.bounds,
            of: creditsButton,
            preferredEdge: .maxY
        )
    }

    /// Toggles the account card from an explicit avatar click or keyboard activation.
    private func showAccount() {
        guard showsAvatar else { return }
        guard userRepo.isSignedIn else {
            onSignIn?()
            return
        }
        if showingAccount, popover?.isShown == true {
            closePopover()
            return
        }
        closePopover()
        accountCard.resetMenuHover()
        accountCard.update()
        let controller = NSViewController()
        controller.view = accountCard
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = controller
        popover.contentSize = accountCard.fittingSize
        self.popover = popover
        showingAccount = true
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .maxY
        )
    }

    /// Dismisses the card before the home coordinator stops generation and clears credentials.
    private func signOut() {
        closePopover()
        onSignOut?()
    }
}
