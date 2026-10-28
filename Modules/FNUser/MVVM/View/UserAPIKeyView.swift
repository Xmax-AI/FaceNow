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

/// Presents credential editing without coupling user preferences to the session.
@MainActor
final class UserAPIKeyView: Canvas, NSTextFieldDelegate {

    /// The preferences edited by the native field.
    @Injected(\.userRepo) private var userRepo: UserRepository

    /// Requests the full login page from the home coordinator.
    var onSignIn: (() -> Void)?

    /// Requests generation cleanup before signing out.
    var onSignOut: (() -> Void)?

    /// Prevents credential changes while generation or cleanup owns the SDK key.
    var settingsLocked = false

    /// Opens the persistent credential editor.
    private lazy var button: Button = {
        let button = Button(icon: .key)
        button.font = Typography.font(size: 12)
        button.iconSize = 14
        button.toolTip = "API Key"
        button.setAccessibilityLabel("API Key")
        button.onClick = { [weak self] in self?.showAccount() }
        return button
    }()

    /// Retains keyboard editing and selection between coalesced updates.
    private lazy var keyField: NSTextField = {
        let field = NSTextField()
        field.delegate = self
        field.placeholderString = "API Key"
        field.font = Typography.font(size: 13)
        field.bezelStyle = .roundedBezel
        field.setAccessibilityLabel("API Key")
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

    /// Owns only the credential popover.
    private var popover: NSPopover?

    /// Creates the credential control for the shared user settings.
    init() {
        super.init()
        addSubview(button)
        update()
    }

    /// Storyboard decoding is unsupported for this programmatic view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Measures the credential pill while preserving the empty-key icon width.
    func preferredWidth(
        controlHeight: CGFloat
    ) -> CGFloat {
        button.title.isEmpty ? controlHeight : min(320, button.preferredWidth)
    }

    /// Updates the pill without replacing an active editor.
    func update() {
        button.title = userRepo.isSignedIn ? userRepo.displayName : userRepo.hasAPIKey ? "API Key" : "Sign in"
        button.toolTip = userRepo.isSignedIn ? "Account and API keys" : "Sign in or use an API key"
    }

    /// Fills the host-provided control frame.
    override func layout() {
        super.layout()
        button.frame = bounds
    }

    /// Dismisses editing during page transitions or application shutdown.
    func closePopover() {
        popover?.close()
        popover = nil
    }

    /// Shows named keys for account users and preserves the original manual-key editor.
    private func showAccount() {
        guard userRepo.isSignedIn else {
            onSignIn?()
            return
        }
        let menu = NSMenu()
        menu.font = Typography.font(size: 13)
        menu.addItem(
            withTitle: userRepo.displayName,
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        if let error = userRepo.errorMessage {
            menu.addItem(
                withTitle: String(error.prefix(90)),
                action: nil,
                keyEquivalent: ""
            )
        }
        for key in userRepo.keys {
            let item = menu.addItem(
                withTitle: key.name,
                action: #selector(selectAccountKey(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = key.uid
            item.state = key.apiKey == userRepo.apiKey ? .on : .off
            item.isEnabled = !settingsLocked && !userRepo.isBusy && !userRepo.isLoadingKeys
        }
        if userRepo.keys.isEmpty {
            let create = menu.addItem(
                withTitle: "Create FaceNow API key",
                action: #selector(createAccountKey),
                keyEquivalent: ""
            )
            create.target = self
            create.isEnabled = !settingsLocked && !userRepo.isBusy && !userRepo.isLoadingKeys
        }
        let reload = menu.addItem(
            withTitle: "Refresh API keys",
            action: #selector(reloadAccountKeys),
            keyEquivalent: ""
        )
        reload.target = self
        reload.isEnabled = !settingsLocked && !userRepo.isBusy && !userRepo.isLoadingKeys
        menu.addItem(.separator())
        let logout = menu.addItem(
            withTitle: "Sign out",
            action: #selector(signOut),
            keyEquivalent: ""
        )
        logout.target = self
        menu.autoenablesItems = false
        menu.popUp(
            positioning: nil,
            at: NSPoint(
                x: 0,
                y: button.bounds.maxY + 4
            ),
            in: button
        )
    }

    /// Selects an existing key only while generation settings are unlocked.
    @objc private func selectAccountKey(
        _ sender: NSMenuItem
    ) {
        guard !settingsLocked, let uid = sender.representedObject as? String else { return }
        userRepo.selectKey(uid: uid)
    }

    /// Creates a key after an explicit menu action.
    @objc private func createAccountKey() {
        guard !settingsLocked else { return }
        Task { await userRepo.createKey() }
    }

    /// Reloads keys without changing a live generation session's credential.
    @objc private func reloadAccountKeys() {
        guard !settingsLocked else { return }
        Task { await userRepo.reloadKeys() }
    }

    /// Delegates logout so the home coordinator can stop generation first.
    @objc private func signOut() { onSignOut?() }

    /// Presents the saved credential and platform help without restarting the session.
    func showEditor() {
        guard userRepo.canAccessHome else {
            onSignIn?()
            return
        }
        closePopover()
        let text = "Get an API key from the Xmax Open Platform."
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
        editor.frame.size = NSSize(
            width: width,
            height: 130
        )
        keyField.stringValue = userRepo.apiKey
        keyField.frame = NSRect(
            x: 16,
            y: 16,
            width: width - 32,
            height: 36
        )
        helpView.frame = NSRect(
            x: 18,
            y: 64,
            width: width - 36,
            height: 18
        )
        helpView.textStorage?.setAttributedString(attributed)
        editor.addSubview(keyField)
        editor.addSubview(helpView)
        keyField.isEnabled = !settingsLocked
        let signIn = Button(
            "Sign in to your account",
            style: .plain
        )
        signIn.frame = NSRect(
            x: 16,
            y: 92,
            width: width - 32,
            height: 26
        )
        signIn.onClick = { [weak self] in
            self?.closePopover()
            self?.onSignIn?()
        }
        editor.subviews.filter { $0 is Button }.forEach { $0.removeFromSuperview() }
        editor.addSubview(signIn)
        let controller = NSViewController()
        controller.view = editor
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.contentSize = editor.frame.size
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
