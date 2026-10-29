//
//  UserLoginFormView.swift
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
#if canImport(FNNetwork)
    import FNNetwork
#endif

/// Presents verification-code and validated API-key sign-in without leaving the login page.
@MainActor
final class UserLoginFormView: Canvas, NSTextFieldDelegate {

    /// The page presenting security-verification sheets.
    weak var presenter: NSViewController?

    /// Presents request failures through the host's existing transient notification.
    var onRequestError: ((String?) -> Void)?

    /// The account owner receiving a successfully verified session.
    @Injected(\.userRepo) private var userRepo: UserRepository

    /// The channel drafts, validation, and resend state owned by this presentation.
    private let viewModel = UserLoginViewModel()

    /// The tenant capabilities used to configure native controls.
    private var configuration: LoginConfiguration? { viewModel.configuration }

    /// The selected verification channel rendered by the segmented control.
    private var method: LoginMethod { viewModel.method }

    /// The API-key form remains on this login page until the repository validates its credential.
    private var usesAPIKey: Bool { viewModel.usesAPIKey }

    /// The in-flight send or sign-in operation, including its security challenge.
    private var operation: Task<Void, Never>?

    /// Limits the sign-in spinner to an explicit login submission, including its security challenge.
    private var isSubmittingLogin = false

    /// The independent public-config request.
    private var configurationTask: Task<Void, Never>?

    /// Lets the existing sign-in action retry a failed configuration request.
    private var configurationFailed = false

    /// Shares request failures with the host toast and existing tooltips without adding status labels.
    private var requestError: String? {
        didSet { onRequestError?(requestError) }
    }

    /// Updates resend labels without retaining a hidden view indefinitely.
    private var ticker: Task<Void, Never>?

    /// Receives account state changes on the main actor.
    private var observation: AnyCancellable?

    /// The bounded page scale currently applied to fonts and layout constants.
    private var layoutScale: CGFloat = 1

    /// The last accessory width, avoiding animation restarts on unrelated form updates.
    private var sendButtonWidth: CGFloat?

    /// Places sign-in below the single credential field in API-key mode.
    private var apiKeyLoginTop: Constraint?

    /// Places sign-in below the verification field in phone and email modes.
    private var codeLoginTop: Constraint?

    /// Preserves the two-row form footprint while allowing compact API-key actions.
    private var termsBottom: Constraint?

    /// Chooses between verification-code channels and API-key sign-in.
    private lazy var methods: TabSwitcher = {
        let view = TabSwitcher(
            titles: [UserStrings.phone, UserStrings.email, UserStrings.apiKey]
        )
        view.font = Typography.font(
            size: 15,
            weight: .medium
        )
        view.onSelectionChanged = { [weak self] index in
            guard let self else { return }
            if index == 2 {
                self.selectAPIKeyMode()
            } else {
                self.switchMethod(index == 0 ? .sms : .email)
            }
        }
        return view
    }()

    /// The shared account input with a noneditable domestic dialing prefix.
    private lazy var accountInput: InputField = {
        let view = InputField()
        view.font = Typography.font(size: 15)
        view.prefix = "+86"
        view.textField.delegate = self
        view.textField.setAccessibilityLabel(UserStrings.phoneLabel)
        view.textField.placeholderString = UserStrings.phonePlaceholder
        return view
    }()

    /// The native account editor keeps its value separate from the fixed dialing prefix.
    private var accountField: NSTextField { accountInput.textField }

    /// The shared masked input used by API-key sign-in.
    private lazy var apiKeyInput: InputField = {
        let view = InputField(secure: true)
        view.font = Typography.font(size: 15)
        view.textField.delegate = self
        view.textField.placeholderString = UserStrings.apiKeyPlaceholder
        view.textField.setAccessibilityLabel(UserStrings.apiKey)
        return view
    }()

    /// The masked native editor retains the alternate sign-in draft.
    private var apiKeyField: NSTextField { apiKeyInput.textField }

    /// The shared verification input reserves space for its inline resend action.
    private lazy var codeInput: InputField = {
        let view = InputField()
        view.font = Typography.font(size: 15)
        view.textField.delegate = self
        view.textField.setAccessibilityLabel(UserStrings.codeLabel)
        view.textField.placeholderString = UserStrings.codePlaceholder
        return view
    }()

    /// The native code editor follows the tenant-configured verification length.
    private var codeField: NSTextField { codeInput.textField }

    /// Sends a code after a fresh security challenge.
    private lazy var sendButton: Button = {
        let view = Button(
            UserStrings.getCode,
            style: .primary
        )
        view.disabledOpacity = 0.65
        view.isEnabled = false
        view.showsShadow = false
        view.cornerRadius = 6
        view.font = Typography.font(size: 12.5)
        view.leadingPadding = 12
        view.trailingPadding = 12
        view.onClick = { [weak self] in self?.run(login: false) }
        return view
    }()

    /// Separates the inline code action from the native editor, matching the phone prefix divider.
    private lazy var sendDivider: Canvas = {
        let view = Canvas(color: Palette.border)
        return view
    }()

    /// Submits the code with a fresh login challenge.
    private lazy var loginButton: Button = {
        let view = Button(
            UserStrings.signIn,
            style: .primary
        )
        view.cornerRadius = 12
        view.shadowScale = 0.5
        view.disabledOpacity = 0.65
        view.isEnabled = false
        view.font = Typography.font(
            size: 16,
            weight: .medium
        )
        view.setAccessibilityLabel(UserStrings.signIn)
        view.onClick = { [weak self] in self?.run(login: true) }
        return view
    }()

    /// Presents the same platform legal destinations as the existing onboarding.
    private lazy var terms: NSTextView = {
        let view = NSTextView()
        view.alphaValue = 0.75
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.linkTextAttributes = [
            .foregroundColor: Palette.accent,
            .underlineStyle: 0,
            .cursor: NSCursor.pointingHand,
        ]
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 2
        let text = UserStrings.agreement
        let value = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: Typography.font(size: 14), .foregroundColor: Palette.secondary,
                .paragraphStyle: paragraph,
            ]
        )
        value.addAttribute(
            .link,
            value: "https://platform.xmaxai.com/docs/resources/terms",
            range: (text as NSString).range(of: UserStrings.termsOfUse)
        )
        value.addAttribute(
            .link,
            value: "https://platform.xmaxai.com/docs/resources/privacy",
            range: (text as NSString).range(of: UserStrings.privacyPolicy)
        )
        view.textStorage?.setAttributedString(value)
        return view
    }()

    /// Creates native controls without opening a camera or sending a code.
    init() {
        super.init()
        [
            methods, accountInput, codeInput, loginButton, terms, apiKeyInput,
        ].forEach(addSubview)
        [sendButton, sendDivider].forEach(codeInput.addSubview)
        configureLayout()
        observation = userRepo.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.update() }
        }
        update()
    }

    /// Storyboard decoding is unsupported for this programmatic view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Updates presentation metrics while preserving native editors, drafts, focus, and legal links.
    func applyLayoutScale(
        _ scale: CGFloat
    ) {
        guard abs(layoutScale - scale) > 0.001 else { return }
        layoutScale = scale
        methods.font = Typography.font(
            size: 15 * scale,
            weight: .medium
        )
        for input in [accountInput, codeInput, apiKeyInput] {
            input.font = Typography.font(size: 15 * scale)
        }
        loginButton.cornerRadius = 12 * scale
        sendButton.cornerRadius = 6 * scale
        sendButton.font = Typography.font(size: 12.5 * scale)
        sendButton.leadingPadding = 12 * scale
        sendButton.trailingPadding = 12 * scale
        loginButton.font = Typography.font(
            size: 16 * scale,
            weight: .medium
        )
        terms.textStorage?.addAttribute(
            .font,
            value: Typography.font(size: 14 * scale),
            range: NSRange(
                location: 0,
                length: terms.textStorage?.length ?? 0
            )
        )
        methods.snp.updateConstraints { make in make.height.equalTo(52 * scale) }
        accountInput.snp.updateConstraints { make in
            make.top.equalTo(methods.snp.bottom).offset(24 * scale)
            make.height.equalTo(54 * scale)
        }
        codeInput.snp.updateConstraints { make in
            make.top.equalTo(accountInput.snp.bottom).offset(16 * scale)
            make.height.equalTo(54 * scale)
        }
        sendButton.snp.updateConstraints { make in
            make.trailing.equalToSuperview().inset(8 * scale)
            make.top.bottom.equalToSuperview().inset(8 * scale)
        }
        sendDivider.snp.updateConstraints { make in
            make.trailing.equalTo(sendButton.snp.leading).offset(-8 * scale)
            make.height.equalTo(20 * scale)
        }
        updateSendButtonWidth(animated: false)
        loginButton.snp.updateConstraints { make in
            make.height.equalTo(54 * scale)
        }
        apiKeyLoginTop?.update(offset: 20 * scale)
        codeLoginTop?.update(offset: 20 * scale)
        terms.snp.updateConstraints { make in
            make.top.equalTo(loginButton.snp.bottom).offset(24 * scale)
        }
        updateChannelLayout()
        needsLayout = true
        needsDisplay = true
    }

    /// Starts public configuration and countdown work only while attached to a window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            shutdown()
            return
        }
        if configuration == nil { loadConfiguration() }
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.update()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    /// Cancels form work and any pending security challenge on dismissal or app shutdown.
    func shutdown() {
        operation?.cancel()
        operation = nil
        isSubmittingLogin = false
        configurationTask?.cancel()
        configurationTask = nil
        ticker?.cancel()
        ticker = nil
    }

    /// Constrains the channel selector, native inputs, legal links, and feedback once.
    private func configureLayout() {
        methods.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
            make.height.equalTo(52)
        }
        accountInput.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(methods.snp.bottom).offset(24)
            make.height.equalTo(54)
        }
        apiKeyInput.snp.makeConstraints { make in
            make.edges.equalTo(accountInput)
        }
        codeInput.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(accountInput.snp.bottom).offset(16)
            make.height.equalTo(54)
        }
        sendButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(8)
            make.top.bottom.equalToSuperview().inset(8)
            make.width.equalTo(sendButton.preferredWidth)
        }
        sendDivider.snp.makeConstraints { make in
            make.trailing.equalTo(sendButton.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
            make.width.equalTo(1)
            make.height.equalTo(20)
        }
        loginButton.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            codeLoginTop = make.top.equalTo(codeInput.snp.bottom).offset(20).constraint
            make.height.equalTo(54)
        }
        loginButton.snp.prepareConstraints { make in
            apiKeyLoginTop = make.top.equalTo(apiKeyInput.snp.bottom).offset(20).constraint
        }
        terms.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(loginButton.snp.bottom).offset(24)
            make.height.equalTo(20)
            termsBottom = make.bottom.equalToSuperview().constraint
        }
    }

    /// Measures wrapped legal text so centering follows the visible form instead of reserved blank space.
    override func layout() {
        let height = ceil(
            terms.attributedString().boundingRect(
                with: NSSize(
                    width: max(1, bounds.width),
                    height: .greatestFiniteMagnitude
                ),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height
        )
        terms.snp.updateConstraints { make in make.height.equalTo(height) }
        super.layout()
    }

    /// Moves unused API-key row space below the actions so the selector and first input stay anchored.
    private func updateChannelLayout() {
        if usesAPIKey {
            codeLoginTop?.deactivate()
            apiKeyLoginTop?.activate()
        } else {
            apiKeyLoginTop?.deactivate()
            codeLoginTop?.activate()
        }
        let unusedRowHeight: CGFloat = usesAPIKey ? 54 + 16 : 0
        termsBottom?.update(inset: unusedRowHeight * layoutScale)
    }

    /// Returns the current destination after normalizing the native editor's value.
    private var destination: String { viewModel.destination(from: accountField.stringValue) }

    /// The selected destination's monotonic resend countdown.
    private var cooldown: Int { viewModel.cooldown(for: destination) }

    /// Whether the selected destination satisfies the platform's format rules.
    private var validAccount: Bool { viewModel.isValidAccount(destination) }

    /// The selected tenant-configured verification-code length.
    private var codeLength: Int { viewModel.codeLength }

    /// Updates enablement from actual work and tenant capabilities without replacing inputs.
    private func update() {
        let busy = operation != nil || userRepo.isBusy || userRepo.isRestoring
        let ready = configuration?.supports(method) == true && configurationTask == nil
        methods.isEnabled = !busy
        methods.selectedIndex = usesAPIKey ? 2 : method == .sms ? 0 : 1
        methods.setEnabled(
            configuration?.enableSmsLogin ?? false,
            at: 0
        )
        methods.setEnabled(
            configuration?.enableEmailLogin ?? false,
            at: 1
        )
        accountInput.isEnabled = !busy
        accountInput.isHidden = usesAPIKey
        accountInput.prefix = method == .sms ? "+86" : nil
        apiKeyInput.isEnabled = !busy
        apiKeyInput.isHidden = !usesAPIKey
        codeInput.isHidden = usesAPIKey
        codeInput.isEnabled = !busy
        apiKeyInput.validationMessage = viewModel.apiKeyValidationMessage
        codeInput.validationMessage = viewModel.codeValidationMessage
        sendButton.isEnabled = ready && !busy && validAccount && cooldown == 0
        sendButton.title = cooldown > 0 ? UserStrings.resendCode(seconds: cooldown) : UserStrings.getCode
        updateSendButtonWidth(animated: true)
        let loading = isSubmittingLogin
        loginButton.title = loading ? "" : UserStrings.signIn
        loginButton.loading = loading
        loginButton.isEnabled =
            !busy
            && (usesAPIKey
                ? !apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                : (ready || configurationFailed) && validAccount && codeField.stringValue.count == codeLength)
        loginButton.toolTip = requestError ?? userRepo.errorMessage
        sendButton.toolTip = requestError
        updateChannelLayout()
    }

    /// Fits the inline action to its current label and moves the divider and editor together.
    private func updateSendButtonWidth(
        animated: Bool
    ) {
        let width = sendButton.preferredWidth
        // Reserve the button, its outer inset, the divider gap, and the one-point divider.
        // InputField retains its standard editor gutter before this accessory region.
        let trailingInset = width + 16 * layoutScale + 1
        guard sendButtonWidth != width || codeInput.trailingInset != trailingInset else { return }
        let shouldAnimate =
            animated && sendButtonWidth != nil && !codeInput.isHiddenOrHasHiddenAncestor
            && ControlMotion.isAnimated(in: codeInput)
        if shouldAnimate { codeInput.layoutSubtreeIfNeeded() }
        sendButtonWidth = width
        let applyWidth = {
            self.sendButton.snp.updateConstraints { make in make.width.equalTo(width) }
            self.codeInput.trailingInset = trailingInset
        }
        if shouldAnimate {
            ControlMotion.animate(in: codeInput) {
                NSAnimationContext.current.allowsImplicitAnimation = true
                applyWidth()
                codeInput.layoutSubtreeIfNeeded()
            }
        } else {
            applyWidth()
        }
    }

    /// Fetches tenant settings and chooses an enabled method without sending a code.
    private func loadConfiguration() {
        guard configurationTask == nil else { return }
        configurationFailed = false
        requestError = nil
        configurationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.configurationTask = nil
                self.update()
            }
            do {
                let settings = try await self.userRepo.loginConfiguration()
                try Task.checkCancellation()
                try self.viewModel.applyConfiguration(settings)
                if !self.usesAPIKey {
                    if !settings.supports(self.method), settings.supports(.email) { self.switchMethod(.email) }
                    self.requestError =
                        settings.enableSmsLogin || settings.enableEmailLogin
                        ? nil : UserStrings.loginUnavailable
                }
            } catch is CancellationError {} catch {
                self.configurationFailed = true
                if !self.usesAPIKey { self.requestError = error.localizedDescription }
            }
        }
        update()
    }

    /// Runs a single code-send or sign-in operation with a fresh security proof.
    private func run(
        login: Bool
    ) {
        if usesAPIKey {
            if login { signInWithAPIKey() }
            return
        }
        if login, configurationFailed {
            loadConfiguration()
            return
        }
        guard operation == nil, !userRepo.isRestoring, let configuration, configuration.supports(method), validAccount
        else { return }
        guard login ? codeField.stringValue.count == codeLength : cooldown == 0 else { return }
        let method = method, destination = destination, code = codeField.stringValue
        requestError = nil
        isSubmittingLogin = login
        operation = Task { [weak self] in
            guard let self else { return }
            defer {
                self.operation = nil
                self.isSubmittingLogin = false
                self.update()
            }
            do {
                let required =
                    login
                    ? configuration.captchaRequiredOnLogin || (method == .sms && configuration.enableCaptcha)
                    : configuration.enableCaptcha
                var proof = CaptchaProof()
                if required {
                    guard let id = configuration.captchaAppId, !id.isEmpty, let presenter = self.presenter else {
                        throw NetworkError.server(
                            code: 400,
                            message: UserStrings.securityUnavailable
                        )
                    }
                    let challenge = UserCaptchaViewController(
                        appID: id,
                        businessState: login ? "login" : "send-\(method.rawValue)-code"
                    )
                    proof = try await challenge.verify(presenting: presenter)
                }
                try Task.checkCancellation()
                if login {
                    try await self.userRepo.signIn(
                        method: method,
                        account: destination,
                        code: code,
                        proof: proof
                    )
                    try Task.checkCancellation()
                    if !self.userRepo.isSignedIn {
                        self.requestError = self.userRepo.errorMessage ?? UserStrings.retrySignIn
                    }
                } else {
                    try await self.userRepo.sendCode(
                        method: method,
                        account: destination,
                        proof: proof
                    )
                    try Task.checkCancellation()
                    self.viewModel.recordCodeSent(
                        to: destination,
                        method: method,
                        cooldown: configuration.cooldown(for: method)
                    )
                    self.window?.makeFirstResponder(self.codeField)
                }
            } catch is CancellationError {} catch {
                guard !Task.isCancelled else { return }
                self.requestError = login
                    ? self.viewModel.recordSignInFailure(error, value: code, method: method) : error.localizedDescription
            }
        }
        update()
    }

    /// Shows API-key input on the same page while retaining the verification-code drafts.
    private func selectAPIKeyMode() {
        guard operation == nil, !userRepo.isBusy, !userRepo.isRestoring else { return }
        viewModel.selectAPIKey(true)
        requestError = nil
        update()
        window?.makeFirstResponder(apiKeyField)
    }

    /// Verifies the submitted key before the account can publish authenticated home access.
    private func signInWithAPIKey() {
        guard operation == nil, !userRepo.isBusy, !userRepo.isRestoring else { return }
        let submittedValue = apiKeyField.stringValue
        let credential = submittedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credential.isEmpty else { return }
        requestError = nil
        isSubmittingLogin = true
        operation = Task { [weak self] in
            guard let self else { return }
            defer {
                self.operation = nil
                self.isSubmittingLogin = false
                self.update()
            }
            do {
                try await self.userRepo.signIn(apiKey: credential)
                try Task.checkCancellation()
                if !self.userRepo.isSignedIn {
                    self.requestError = self.userRepo.errorMessage ?? UserStrings.retrySignIn
                }
            } catch is CancellationError {} catch {
                guard !Task.isCancelled else { return }
                self.requestError = self.viewModel.recordSignInFailure(
                    error,
                    value: submittedValue,
                    usingAPIKey: true
                )
            }
        }
        update()
    }

    /// Restores the selected channel's independent destination and code draft.
    private func switchMethod(
        _ next: LoginMethod
    ) {
        let draft = viewModel.switchMethod(
            next,
            account: accountField.stringValue,
            code: codeField.stringValue
        )
        accountField.stringValue = draft.account
        codeField.stringValue = draft.code
        accountField.placeholderString = next == .sms ? UserStrings.phonePlaceholder : UserStrings.emailPlaceholder
        accountField.setAccessibilityLabel(next == .sms ? UserStrings.phoneLabel : UserStrings.emailLabel)
        requestError = nil
        update()
    }

    /// Restricts codes to ASCII digits and invalidates a code when its destination changes.
    func controlTextDidChange(
        _ notification: Notification
    ) {
        guard let field = notification.object as? NSTextField else { return }
        if field === codeField {
            codeField.stringValue = viewModel.filteredCode(codeField.stringValue)
            viewModel.didEditVerificationCode(codeField.stringValue)
        } else if field === accountField {
            codeField.stringValue = ""
            viewModel.didEditVerificationCode(codeField.stringValue)
        } else if field === apiKeyField {
            viewModel.didEditAPIKey(apiKeyField.stringValue)
        }
        requestError = nil
        update()
    }

    /// Submits a complete form with Return while preserving normal native editing commands.
    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        if loginButton.isEnabled { run(login: true) }
        return true
    }
}
