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

    /// The independent public-config request.
    private var configurationTask: Task<Void, Never>?

    /// Updates resend labels without retaining a hidden view indefinitely.
    private var ticker: Task<Void, Never>?

    /// Receives account state changes on the main actor.
    private var observation: AnyCancellable?

    /// Chooses between tenant-enabled login methods.
    private lazy var methods: TabSwitcher = {
        let view = TabSwitcher(
            titles: ["Phone", "Email"]
        )
        view.onSelectionChanged = { [weak self] index in self?.switchMethod(index == 0 ? .sms : .email) }
        return view
    }()

    /// The shared account input with a noneditable domestic dialing prefix.
    private lazy var accountInput: InputField = {
        let view = InputField()
        view.prefix = "+86"
        view.textField.delegate = self
        view.textField.setAccessibilityLabel("Phone number")
        view.textField.placeholderString = "Enter your phone number"
        return view
    }()

    /// The native account editor keeps its value separate from the fixed dialing prefix.
    private var accountField: NSTextField { accountInput.textField }

    /// The shared masked input used by API-key sign-in.
    private lazy var apiKeyInput: InputField = {
        let view = InputField(secure: true)
        view.textField.delegate = self
        view.textField.placeholderString = "API key"
        view.textField.setAccessibilityLabel("API Key")
        return view
    }()

    /// The masked native editor retains the alternate sign-in draft.
    private var apiKeyField: NSTextField { apiKeyInput.textField }

    /// Explains which credential can be used by the alternate sign-in method.
    private lazy var apiKeyHint: NSTextField = {
        let view = makeLabel(
            "Use an active API key from your Xmax account.",
            size: 12,
            color: Palette.secondary
        )
        view.maximumNumberOfLines = 2
        view.lineBreakMode = .byWordWrapping
        return view
    }()

    /// The shared verification input reserves space for its inline resend action.
    private lazy var codeInput: InputField = {
        let view = InputField()
        view.trailingInset = 104
        view.textField.delegate = self
        view.textField.setAccessibilityLabel("Verification code")
        view.textField.placeholderString = "Enter verification code"
        return view
    }()

    /// The native code editor follows the tenant-configured verification length.
    private var codeField: NSTextField { codeInput.textField }

    /// Sends a code after a fresh security challenge.
    private lazy var sendButton: Button = {
        let view = Button(
            "Get code",
            style: .pill
        )
        view.showsShadow = false
        view.font = Typography.font(size: 12)
        view.onClick = { [weak self] in self?.run(login: false) }
        return view
    }()

    /// Submits the code with a fresh login challenge.
    private lazy var loginButton: Button = {
        let view = Button(
            "Sign in",
            style: .primary
        )
        view.onClick = { [weak self] in self?.run(login: true) }
        return view
    }()

    /// Presents the same platform legal destinations as the existing onboarding.
    private lazy var terms: NSTextView = {
        let view = NSTextView()
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
        let text = "By signing in, you are agreeing to the Terms of Use and Privacy Policy."
        let value = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: Typography.font(size: 12), .foregroundColor: Palette.secondary,
                .paragraphStyle: paragraph,
            ]
        )
        value.addAttribute(
            .link,
            value: "https://platform.xmaxsi.com/docs/resources/terms",
            range: (text as NSString).range(of: "Terms of Use")
        )
        value.addAttribute(
            .link,
            value: "https://platform.xmaxsi.com/docs/resources/privacy",
            range: (text as NSString).range(of: "Privacy Policy")
        )
        view.textStorage?.setAttributedString(value)
        return view
    }()

    /// Displays request failures and successful code-send feedback in place.
    private lazy var status: NSTextField = {
        let view = makeLabel(
            size: 12,
            color: Palette.secondary
        )
        view.maximumNumberOfLines = 3
        view.lineBreakMode = .byWordWrapping
        return view
    }()

    /// Retries a failed configuration or saved-session lookup.
    private lazy var retryButton: Button = {
        let view = Button(
            "Retry",
            style: .plain
        )
        view.onClick = { [weak self] in self?.retry() }
        return view
    }()

    /// Switches input modes within the login page without granting home access.
    private lazy var manualButton: Button = {
        let view = Button(
            "Use an API key instead",
            style: .plain
        )
        view.onClick = { [weak self] in self?.toggleAPIKeyMode() }
        return view
    }()

    /// Creates native controls without opening a camera or sending a code.
    init() {
        super.init()
        [
            methods, accountInput, codeInput, loginButton, terms, status,
            retryButton, manualButton, apiKeyInput, apiKeyHint,
        ].forEach(addSubview)
        codeInput.addSubview(sendButton)
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

    /// Reserves a stable form height across feedback and countdown changes.
    override var fittingSize: NSSize {
        NSSize(
            width: 480,
            height: 448
        )
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
        configurationTask?.cancel()
        configurationTask = nil
        ticker?.cancel()
        ticker = nil
    }

    /// Constrains the channel selector, native inputs, legal links, and feedback once.
    private func configureLayout() {
        methods.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
            make.height.equalTo(42)
        }
        accountInput.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(methods.snp.bottom).offset(32)
            make.height.equalTo(56)
        }
        apiKeyInput.snp.makeConstraints { make in
            make.edges.equalTo(accountInput)
        }
        apiKeyHint.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(accountInput.snp.bottom).offset(20)
            make.height.equalTo(56)
        }
        codeInput.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(accountInput.snp.bottom).offset(20)
            make.height.equalTo(56)
        }
        sendButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(6)
            make.top.bottom.equalToSuperview().inset(6)
            make.width.equalTo(104)
        }
        loginButton.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(codeInput.snp.bottom).offset(28)
            make.height.equalTo(56)
        }
        terms.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(loginButton.snp.bottom).offset(18)
            make.height.equalTo(44)
        }
        status.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.trailing.equalTo(retryButton.snp.leading)
            make.top.equalTo(terms.snp.bottom).offset(12)
            make.height.equalTo(32)
        }
        retryButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.top.equalTo(status).offset(-2)
            make.width.equalTo(48)
            make.height.equalTo(26)
        }
        manualButton.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(status.snp.bottom).offset(20)
            make.height.equalTo(28)
        }
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
        apiKeyHint.isHidden = !usesAPIKey
        codeInput.isHidden = usesAPIKey
        codeInput.isEnabled = !busy
        sendButton.isEnabled = ready && !busy && validAccount && cooldown == 0
        sendButton.title = cooldown > 0 ? "Resend (\(cooldown)s)" : "Get code"
        loginButton.loading = busy
        loginButton.title = userRepo.isRestoring ? "Restoring session…" : busy ? "Please wait…" : "Sign in"
        loginButton.isEnabled =
            !busy
            && (usesAPIKey
                ? !apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                : ready && validAccount && codeField.stringValue.count == codeLength)
        manualButton.isEnabled = !busy
        manualButton.title = usesAPIKey ? "Use phone number or email" : "Use an API key instead"
        retryButton.isHidden = configuration != nil && !userRepo.hasSavedSession
        retryButton.isEnabled = !busy && configurationTask == nil
        if status.stringValue.isEmpty, let message = userRepo.errorMessage { status.stringValue = message }
    }

    /// Fetches tenant settings and chooses an enabled method without sending a code.
    private func loadConfiguration() {
        guard configurationTask == nil else { return }
        status.stringValue = "Loading sign-in options…"
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
                    self.status.stringValue =
                        settings.enableSmsLogin || settings.enableEmailLogin
                        ? "" : "Verification-code login is currently unavailable."
                }
            } catch is CancellationError {} catch {
                if !self.usesAPIKey { self.status.stringValue = error.localizedDescription }
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
        guard operation == nil, !userRepo.isRestoring, let configuration, configuration.supports(method), validAccount
        else { return }
        guard login ? codeField.stringValue.count == codeLength : cooldown == 0 else { return }
        let method = method, destination = destination, code = codeField.stringValue
        status.stringValue = ""
        operation = Task { [weak self] in
            guard let self else { return }
            defer {
                self.operation = nil
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
                            message: "Security verification is unavailable. Please try again."
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
                        self.status.stringValue = self.userRepo.errorMessage ?? "Please try signing in again."
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
                    self.status.stringValue = "Verification code sent."
                    self.window?.makeFirstResponder(self.codeField)
                }
            } catch is CancellationError {} catch { self.status.stringValue = error.localizedDescription }
        }
        update()
    }

    /// Shows API-key input on the same page while retaining the verification-code drafts.
    private func toggleAPIKeyMode() {
        guard operation == nil, !userRepo.isBusy, !userRepo.isRestoring else { return }
        viewModel.selectAPIKey(!usesAPIKey)
        methods.selectedIndex = usesAPIKey ? nil : method == .sms ? 0 : 1
        status.stringValue = ""
        update()
        window?.makeFirstResponder(usesAPIKey ? apiKeyField : accountField)
    }

    /// Verifies the submitted key before the account can publish authenticated home access.
    private func signInWithAPIKey() {
        guard operation == nil, !userRepo.isBusy, !userRepo.isRestoring else { return }
        let credential = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credential.isEmpty else { return }
        status.stringValue = ""
        operation = Task { [weak self] in
            guard let self else { return }
            defer {
                self.operation = nil
                self.update()
            }
            do {
                try await self.userRepo.signIn(apiKey: credential)
                try Task.checkCancellation()
                if !self.userRepo.isSignedIn {
                    self.status.stringValue = self.userRepo.errorMessage ?? "Please try signing in again."
                }
            } catch is CancellationError {} catch { self.status.stringValue = error.localizedDescription }
        }
        update()
    }

    /// Retries only a read operation when configuration or saved-session validation failed.
    private func retry() {
        status.stringValue = ""
        if configuration == nil { loadConfiguration() }
        if userRepo.hasSavedSession {
            operation = Task { [weak self] in
                guard let self else { return }
                defer {
                    self.operation = nil
                    self.update()
                }
                await self.userRepo.restore()
                self.status.stringValue = self.userRepo.errorMessage ?? ""
            }
            update()
        }
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
        methods.selectedIndex = next == .sms ? 0 : 1
        accountField.stringValue = draft.account
        codeField.stringValue = draft.code
        accountField.placeholderString = next == .sms ? "Enter your phone number" : "Enter your email address"
        accountField.setAccessibilityLabel(next == .sms ? "Phone number" : "Email address")
        status.stringValue = ""
        update()
    }

    /// Restricts codes to ASCII digits and invalidates a code when its destination changes.
    func controlTextDidChange(
        _ notification: Notification
    ) {
        guard let field = notification.object as? NSTextField else { return }
        if field === codeField {
            codeField.stringValue = viewModel.filteredCode(codeField.stringValue)
        } else if field === accountField {
            codeField.stringValue = ""
        }
        status.stringValue = ""
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
