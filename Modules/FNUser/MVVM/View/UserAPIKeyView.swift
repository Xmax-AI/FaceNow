//
//  UserAPIKeyView.swift
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

/// Presents credential editing without coupling user preferences to the session.
@MainActor
final class UserAPIKeyView: Canvas, NSTextFieldDelegate {

    /// The preferences edited by the native field.
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

    /// Prevents credential changes while generation or cleanup owns the SDK key.
    var settingsLocked = false

    /// Uses native fonts for the shared generation header while preserving home typography.
    var usesSystemFont = false {
        didSet {
            guard usesSystemFont != oldValue else { return }
            button.font =
                usesSystemFont
                ? .systemFont(ofSize: ToolbarControlMetrics.fontSize, weight: .semibold)
                : Typography.font(size: ToolbarControlMetrics.fontSize, weight: .semibold)
            creditsButton.font =
                usesSystemFont
                ? .systemFont(ofSize: ToolbarControlMetrics.fontSize, weight: .medium)
                : Typography.font(size: ToolbarControlMetrics.fontSize)
        }
    }

    /// Opens the existing account menu from a circular text avatar.
    private lazy var button: ToolbarButton = {
        let button = ToolbarButton(
            style: .primary,
            shape: .circle,
            weight: .semibold
        )
        button.foregroundColor = .white
        button.onClick = { [weak self] in self?.showAccount() }
        button.onPointerHoverChanged = { [weak self] hovering in
            self?.accountHoverChanged(hovering)
        }
        return button
    }()

    /// Displays server-confirmed credits and opens the platform credit page.
    private lazy var creditsButton: ToolbarButton = {
        let button = ToolbarButton()
        button.symbolName = "bolt.fill"
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

    /// Retains keyboard editing and selection between coalesced updates.
    private lazy var keyField: NSTextField = {
        let field = NSTextField()
        field.delegate = self
        field.placeholderString = UserStrings.apiKey
        field.font = Typography.font(size: 13)
        field.bezelStyle = .roundedBezel
        field.setAccessibilityLabel(UserStrings.apiKey)
        return field
    }()

    /// Contains the editor and platform help link.
    private lazy var editor: Canvas = {
        let view = Canvas()
        return view
    }()

    /// Displays the API platform link using native text selection.
    private lazy var helpView: NSTextView = {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.linkTextAttributes = [
            .foregroundColor: Palette.accent,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        return view
    }()

    /// Whether the current transient popover is showing the account card.
    private var showingAccount = false

    /// Distinguishes a hover warning from account and credential popovers.
    private var showingCredits = false

    /// Keeps the warning visible while either hover surface contains the pointer.
    private var creditsButtonHovered = false
    private var creditsPopoverHovered = false

    /// Owns the short hover delays and cancels them on page or session changes.
    private var creditsHoverTask: Task<Void, Never>?

    /// Keeps the account card visible while either its avatar or content is hovered.
    private var accountButtonHovered = false
    private var accountPopoverHovered = false

    /// Owns account-card entry and dismissal delays independently of the credit warning.
    private var accountHoverTask: Task<Void, Never>?

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
        view.onHoverChanged = { [weak self] hovering in
            guard let self, self.showingAccount else { return }
            self.accountPopoverHovered = hovering
            if hovering {
                self.accountHoverTask?.cancel()
                self.accountHoverTask = nil
            } else {
                self.scheduleAccountDismissal()
            }
        }
        return view
    }()

    /// Owns the single account, credential, or credit-warning popover.
    private var popover: NSPopover?

    /// Creates the credential control for the shared user settings.
    init() {
        super.init()
        [creditsButton, button].forEach(addSubview)
        button.snp.makeConstraints { make in
            make.trailing.top.bottom.equalToSuperview()
        }
        creditsButton.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.trailing.equalTo(button.snp.leading).offset(-ToolbarControlMetrics.spacing)
        }
        update()
    }

    /// Storyboard decoding is unsupported for this programmatic view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Reserves separate, aligned areas for the credit readout and circular avatar.
    func preferredWidth(
        controlHeight: CGFloat
    ) -> CGFloat {
        button.preferredWidth(controlHeight: controlHeight) + ToolbarControlMetrics.spacing
            + creditsButton.preferredWidth
    }

    /// Updates the pill without replacing an active editor.
    func update() {
        button.title = viewModel.avatarText
        button.symbolName = button.title.isEmpty ? "person.fill" : nil
        button.toolTip = nil
        button.setAccessibilityLabel(AccountStrings.accountAccessibility(name: userRepo.displayName))
        creditsButton.title = viewModel.creditsText
        creditsButton.style = viewModel.showsLowCreditsWarning ? .destructive : .pill
        creditsButton.toolTip = viewModel.showsLowCreditsWarning ? nil : viewModel.creditsHelp
        creditsButton.setAccessibilityLabel(AccountStrings.balanceAccessibility(balance: viewModel.creditsText))
        creditsButton.setAccessibilityHelp(viewModel.creditsHelp)
        if !viewModel.showsLowCreditsWarning {
            creditsHoverTask?.cancel()
            creditsHoverTask = nil
            if showingCredits { closePopover() }
        }
        if !userRepo.isSignedIn {
            accountHoverTask?.cancel()
            accountHoverTask = nil
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

    /// Dismisses editing during page transitions or application shutdown.
    func closePopover() {
        creditsHoverTask?.cancel()
        creditsHoverTask = nil
        accountHoverTask?.cancel()
        accountHoverTask = nil
        showingCredits = false
        creditsPopoverHovered = false
        if showingAccount { accountCard.resetMenuHover() }
        showingAccount = false
        accountPopoverHovered = false
        popover?.close()
        popover = nil
    }

    /// Cancels hover work when the owning page leaves its native window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            creditsButtonHovered = false
            accountButtonHovered = false
            closePopover()
        }
    }

    /// Prevents a hidden page from leaving an independent popover visible.
    override func viewDidHide() {
        super.viewDidHide()
        creditsButtonHovered = false
        accountButtonHovered = false
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
        guard popover?.isShown != true || showingAccount || showingCredits else { return }
        if showingCredits, popover?.isShown == true { return }
        // End the previous hover lifecycle before starting the new card's entry delay.
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

    /// Presents the warning only while the red pill is visible and key editing is inactive.
    private func showCreditsWarning() {
        guard viewModel.showsLowCreditsWarning, window?.isVisible == true,
            !isHiddenOrHasHiddenAncestor,
            popover?.isShown != true || showingAccount || showingCredits
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

    /// Shows a signed-in account on hover without triggering login or interrupting key editing.
    private func accountHoverChanged(
        _ hovering: Bool
    ) {
        accountButtonHovered = hovering
        accountHoverTask?.cancel()
        accountHoverTask = nil
        guard hovering else {
            scheduleAccountDismissal()
            return
        }
        guard userRepo.isSignedIn else { return }
        guard popover?.isShown != true || showingAccount || showingCredits else { return }
        if showingAccount, popover?.isShown == true { return }
        closePopover()
        accountHoverTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard let self, self.accountButtonHovered, self.userRepo.isSignedIn,
                self.window?.isVisible == true, !self.isHiddenOrHasHiddenAncestor,
                self.popover?.isShown != true || self.showingAccount || self.showingCredits
            else { return }
            self.showAccount()
        }
    }

    /// Leaves a short bridge between the avatar and its account card before dismissing it.
    private func scheduleAccountDismissal() {
        guard showingAccount, !accountButtonHovered, !accountPopoverHovered else { return }
        accountHoverTask?.cancel()
        accountHoverTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self, self.showingAccount,
                !self.accountButtonHovered, !self.accountPopoverHovered
            else { return }
            self.closePopover()
        }
    }

    /// Presents the account card on hover, retaining click and keyboard access as well.
    private func showAccount() {
        guard userRepo.isSignedIn else {
            onSignIn?()
            return
        }
        if showingAccount, popover?.isShown == true { return }
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

    /// Presents the saved credential and platform help without restarting the session.
    func showEditor() {
        guard userRepo.canAccessHome else {
            onSignIn?()
            return
        }
        closePopover()
        let text = AccountStrings.accountGetAnAPIKeyFromTheXmaxOpenPlatform
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: Typography.font(size: 12), .foregroundColor: Palette.secondary,
            ]
        )
        attributed.addAttribute(
            .link,
            value: "https://platform.xmaxsi.com/api-keys",
            range: (text as NSString).range(of: "Xmax Open Platform")
        )
        let width = max(292, ceil(attributed.size().width) + 40)
        editor.snp.remakeConstraints { make in
            make.width.equalTo(width)
            make.height.equalTo(130)
        }
        keyField.stringValue = userRepo.apiKey
        helpView.textStorage?.setAttributedString(attributed)
        editor.addSubview(keyField)
        editor.addSubview(helpView)
        keyField.snp.remakeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(36)
        }
        helpView.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(18)
            make.top.equalTo(keyField.snp.bottom).offset(12)
            make.height.equalTo(18)
        }
        keyField.isEnabled = !settingsLocked
        let signIn = Button(
            AccountStrings.accountSignInToYourAccount,
            style: .plain
        )
        signIn.onClick = { [weak self] in
            self?.closePopover()
            self?.onSignIn?()
        }
        editor.subviews.filter { $0 is Button }.forEach { $0.removeFromSuperview() }
        editor.addSubview(signIn)
        signIn.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.top.equalTo(helpView.snp.bottom).offset(10)
            make.height.equalTo(26)
        }
        let controller = NSViewController()
        controller.view = editor
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.contentSize = editor.fittingSize
        self.popover = popover
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .maxY
        )
        keyField.window?.makeFirstResponder(keyField)
    }

    /// Persists committed native field changes through FNUser.
    func controlTextDidChange(
        _ notification: Notification
    ) {
        guard notification.object as? NSTextField === keyField, !settingsLocked, userRepo.canAccessHome else { return }
        userRepo.apiKey = keyField.stringValue
    }

    /// Closes the editor for Return and Escape without interfering with other commands.
    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:))
            || commandSelector == #selector(NSResponder.cancelOperation(_:))
        {
            closePopover()
            return true
        }
        return false
    }
}
