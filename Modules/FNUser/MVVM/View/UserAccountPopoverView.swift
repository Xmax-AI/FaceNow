//
//  UserAccountPopoverView.swift
//  FaceNow
//

import AppKit
import SnapKit

/// Presents the account identity followed by policy links and sign-out.
@MainActor
final class UserAccountPopoverView: Canvas {

    /// Opens the privacy policy through the owning account coordinator.
    var onPrivacyPolicy: (() -> Void)?

    /// Opens the user agreement through the owning account coordinator.
    var onUserAgreement: (() -> Void)?

    /// Opens the existing credit purchase page through the account coordinator.
    var onRecharge: (() -> Void)?

    /// Opens the account usage page through the account coordinator.
    var onUsage: (() -> Void)?

    /// Requests session cleanup and logout through the owning account coordinator.
    var onSignOut: (() -> Void)?

    /// Tracks pointer movement across the entire card and its child controls.
    private var hoverArea: NSTrackingArea?

    /// A single background moves between actions instead of fading four independent fills.
    private let menuHoverLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = Palette.surface.cgColor
        layer.opacity = 0
        return layer
    }()

    /// The enabled action currently under the pointer, independent of button event ordering.
    private weak var hoveredAction: Button?

    /// Derives account labels without storing another copy of authentication state.
    private let viewModel = UserAccountViewModel()

    /// Groups the avatar, masked identifier, balance, and recharge action on a light gray surface.
    private lazy var identity: Canvas = {
        let view = Canvas(
            color: Palette.surface,
            radius: 12
        )
        return view
    }()

    /// Centers the masked account identifier and balance together beside the avatar.
    private lazy var details: Canvas = {
        let view = Canvas()
        return view
    }()

    /// The passive avatar matches the application's account entry point.
    private lazy var avatar: Button = {
        let view = Button(style: .primary)
        view.font = Typography.font(
            size: 13,
            weight: .semibold
        )
        view.leadingPadding = 0
        view.trailingPadding = 0
        view.iconSize = 16
        view.foregroundColor = .white
        view.passive = true
        view.isEnabled = false
        view.showsShadow = false
        view.setAccessibilityElement(false)
        return view
    }()

    /// Keeps the account identifier selectable within the card.
    private lazy var name: NSTextField = {
        let view = makeLabel(
            size: 13,
            color: Palette.secondary,
            weight: .semibold
        )
        view.lineBreakMode = .byTruncatingMiddle
        view.isSelectable = true
        return view
    }()

    /// Shows the same server-confirmed balance as the account header in smaller text.
    private lazy var credits: NSTextField = {
        let view = makeLabel(
            size: 10.5,
            color: Palette.secondary
        )
        view.lineBreakMode = .byTruncatingTail
        return view
    }()

    /// Opens the existing credit purchase page without changing the authenticated session.
    private lazy var rechargeButton: Button = {
        let view = Button(
            AccountStrings.accountBuyCredits,
            style: .primary
        )
        view.font = Typography.font(
            size: 11,
            weight: .medium
        )
        view.cornerRadius = 8
        view.foregroundColor = .white
        view.leadingPadding = 10
        view.trailingPadding = 10
        view.showsShadow = false
        view.setAccessibilityLabel(AccountStrings.accountBuyCredits)
        view.onClick = { [weak self] in self?.onRecharge?() }
        return view
    }()

    /// Opens the account's usage history.
    private lazy var usageButton: Button = {
        let view = makeAction(
            AccountStrings.accountViewUsage,
            symbol: "chart.bar"
        )
        view.onClick = { [weak self] in self?.onUsage?() }
        return view
    }()

    /// Opens the existing product privacy policy.
    private lazy var privacyButton: Button = {
        let view = makeAction(
            AccountStrings.privacyPolicy,
            symbol: "hand.raised"
        )
        view.onClick = { [weak self] in self?.onPrivacyPolicy?() }
        return view
    }()

    /// Opens the existing product user agreement.
    private lazy var agreementButton: Button = {
        let view = makeAction(
            AccountStrings.termsOfUse,
            symbol: "doc.text"
        )
        view.onClick = { [weak self] in self?.onUserAgreement?() }
        return view
    }()

    /// Ends the current account session through its existing cleanup flow.
    private lazy var signOutButton: Button = {
        let view = makeAction(
            AccountStrings.accountSignOut,
            symbol: "rectangle.portrait.and.arrow.right"
        )
        view.onClick = { [weak self] in self?.onSignOut?() }
        return view
    }()

    /// Creates the persistent card using native constraint-based controls.
    init() {
        super.init(
            color: .white,
            radius: 16
        )
        layer?.masksToBounds = true
        layer?.insertSublayer(
            menuHoverLayer,
            at: 0
        )
        [identity, usageButton, privacyButton, agreementButton, signOutButton].forEach(addSubview)
        [avatar, details, rechargeButton].forEach(identity.addSubview)
        [name, credits].forEach(details.addSubview)
        configureLayout()
        update()
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Refreshes the account identity, shared balance, and account action availability.
    func update() {
        avatar.title = viewModel.avatarText
        avatar.symbolName = avatar.title.isEmpty ? "person.fill" : nil
        name.stringValue = viewModel.accountTitle
        name.toolTip = viewModel.accountTitle
        credits.stringValue = AccountStrings.balanceTitle(balance: viewModel.creditsText)
        credits.toolTip = viewModel.creditsHelp
        credits.setAccessibilityLabel(AccountStrings.balanceAccessibility(balance: viewModel.creditsText))
        rechargeButton.isEnabled = viewModel.canRecharge
        signOutButton.isEnabled = viewModel.canSignOut
        updateMenuHover()
    }

    /// Keeps the decorative layer aligned without assigning child-view frames.
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        menuHoverLayer.frame = bounds
        CATransaction.commit()
        updateMenuHoverBackground()
    }

    /// Clears stale pointer presentation before the account card is reused.
    func resetMenuHover() {
        hoveredAction = nil
        menuHoverLayer.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        menuHoverLayer.opacity = 0
        CATransaction.commit()
    }

    /// Stops hidden or detached cards from retaining the previous highlighted row.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { resetMenuHover() }
    }

    /// Resets pointer presentation when an ancestor hides the card.
    override func viewDidHide() {
        super.viewDidHide()
        resetMenuHover()
    }

    /// Refreshes pointer tracking when the native account card changes size.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        hoverArea = area
    }

    /// Highlights the action under the pointer without changing popover visibility.
    override func mouseEntered(
        with event: NSEvent
    ) {
        updateMenuHover()
    }

    /// Reconciles the single active row even if native enter and exit events arrive out of order.
    override func mouseMoved(
        with event: NSEvent
    ) {
        updateMenuHover()
    }

    /// Clears the highlighted action while keeping the click-opened account card visible.
    override func mouseExited(
        with event: NSEvent
    ) {
        hoveredAction = nil
        updateMenuHoverBackground()
    }

    /// Resolves one enabled action from the actual pointer location in the popover window.
    private func updateMenuHover() {
        guard let window, window.isVisible, !isHiddenOrHasHiddenAncestor else {
            resetMenuHover()
            return
        }
        let point = convert(
            window.mouseLocationOutsideOfEventStream,
            from: nil
        )
        hoveredAction = [usageButton, privacyButton, agreementButton, signOutButton].first { action in
            action.isEnabled && action.frame.contains(point)
        }
        updateMenuHoverBackground()
    }

    /// Retargets one rounded highlight from its current presentation using shared control timing.
    private func updateMenuHoverBackground() {
        if let action = hoveredAction {
            let rect = convert(
                action.bounds,
                from: action
            ).insetBy(
                dx: 0.5,
                dy: 0.5
            )
            let path = CGPath(
                roundedRect: rect,
                cornerWidth: 12,
                cornerHeight: 12,
                transform: nil
            )
            ControlMotion.set(
                path,
                for: "path",
                on: menuHoverLayer,
                in: self
            )
        }
        ControlMotion.set(
            hoveredAction == nil ? Float(0) : Float(1),
            for: "opacity",
            on: menuHoverLayer,
            in: self
        )
    }

    /// Gives each list action the same leading icon, text alignment, and hit area.
    private func makeAction(
        _ title: String,
        symbol: String
    ) -> Button {
        let view = Button(
            title,
            style: .plain
        )
        view.alignment = .left
        view.symbolName = symbol
        view.iconSize = 16
        view.iconSpacing = 10
        view.leadingPadding = 12
        view.trailingPadding = 12
        view.cornerRadius = 12
        view.onHoverChanged = { [weak self] _ in self?.updateMenuHover() }
        view.foregroundColor = Palette.secondary
        view.showsShadow = false
        view.font = Typography.font(size: 13)
        return view
    }

    /// Shares a compact content width and consistent spacing across the account actions.
    private func configureLayout() {
        snp.makeConstraints { make in make.width.equalTo(340) }
        identity.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(10)
            make.height.equalTo(68)
        }
        avatar.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
            make.size.equalTo(36)
        }
        details.snp.makeConstraints { make in
            make.leading.equalTo(avatar.snp.trailing).offset(10)
            make.trailing.equalTo(rechargeButton.snp.leading).offset(-12)
            make.centerY.equalToSuperview()
        }
        name.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        credits.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalTo(name.snp.bottom).offset(4)
        }
        rechargeButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(12)
            make.centerY.equalToSuperview()
            make.width.equalTo(88)
            make.height.equalTo(28)
        }
        usageButton.snp.makeConstraints { make in
            make.leading.trailing.equalTo(identity)
            make.top.equalTo(identity.snp.bottom).offset(8)
            make.height.equalTo(34)
        }
        privacyButton.snp.makeConstraints { make in
            make.leading.trailing.height.equalTo(usageButton)
            make.top.equalTo(usageButton.snp.bottom).offset(2)
        }
        agreementButton.snp.makeConstraints { make in
            make.leading.trailing.height.equalTo(privacyButton)
            make.top.equalTo(privacyButton.snp.bottom).offset(2)
        }
        signOutButton.snp.makeConstraints { make in
            make.leading.trailing.height.equalTo(privacyButton)
            make.top.equalTo(agreementButton.snp.bottom).offset(2)
            make.bottom.equalToSuperview().inset(10)
        }
    }
}
