//
//  RechargeDialogView.swift
//  FaceNow
//

import AppKit
import SnapKit

/// Presents a centered credit notice while keeping the covered page inactive.
@MainActor
final class RechargeDialogView: Canvas {

    /// Routes explicit recharge through the home coordinator.
    var onRecharge: (() -> Void)?

    /// Dismisses the notice without opening the credit page.
    var onDismiss: (() -> Void)?

    /// Prevents repeated actions and click-through during the closing fade.
    private(set) var isDismissing = false

    /// Keeps removal tied to this view's animation and window lifetime.
    private var dismissalTask: Task<Void, Never>?

    /// Dims the entire app content behind the notice.
    private lazy var backdrop: Canvas = {
        let view = Canvas(color: .black.withAlphaComponent(0.35))
        view.setAccessibilityElement(false)
        return view
    }()

    /// Matches the reference's compact white card and rounded corners.
    private lazy var card: Canvas = {
        let view = Canvas(
            color: .white,
            radius: 14
        )
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowOpacity = 0.16
        view.layer?.shadowRadius = 24
        view.layer?.shadowOffset = CGSize(
            width: 0,
            height: -6
        )
        view.setAccessibilityRole(.group)
        view.setAccessibilityModal(true)
        view.setAccessibilityLabel(AccountStrings.insufficientCredits)
        return view
    }()

    /// Presents the complete localized notice as the card's only heading.
    private lazy var title: NSTextField = {
        let view = NSTextField(wrappingLabelWithString: AccountStrings.insufficientCredits)
        view.font = Typography.font(
            size: 20,
            weight: .semibold
        )
        view.textColor = Palette.text
        view.alignment = .center
        return view
    }()

    /// Dismisses the notice with a quiet outlined action on the left.
    private lazy var laterButton: Button = {
        let view = Button(
            AccountStrings.rechargeLater,
            style: .plain
        )
        view.font = Typography.font(
            size: 14,
            weight: .medium
        )
        view.cornerRadius = 9
        view.showsShadow = false
        view.focusRingType = .none
        view.restingBackgroundColor = .white
        view.hoverBackgroundColor = Palette.surface
        view.foregroundColor = Palette.softText
        view.layer?.cornerRadius = 9
        view.layer?.borderWidth = 1
        view.layer?.borderColor = Palette.border.cgColor
        view.keyEquivalent = "\u{1b}"
        view.keyEquivalentModifierMask = []
        view.onClick = { [weak self] in
            guard let self, !self.isDismissing else { return }
            self.onDismiss?()
        }
        return view
    }()

    /// Opens recharge through the emphasized blue action on the right.
    private lazy var rechargeButton: Button = {
        let view = Button(
            AccountStrings.rechargeNow,
            style: .primary
        )
        view.font = Typography.font(
            size: 14,
            weight: .medium
        )
        view.cornerRadius = 9
        view.showsShadow = false
        view.focusRingType = .none
        view.keyEquivalent = "\r"
        view.keyEquivalentModifierMask = []
        view.onClick = { [weak self] in
            guard let self, !self.isDismissing else { return }
            self.onRecharge?()
        }
        return view
    }()

    /// Receives keyboard focus while the dialog is closing.
    override var acceptsFirstResponder: Bool { true }

    /// Builds the static localized notice without requesting balance or opening a URL.
    init() {
        super.init()
        [backdrop, card].forEach(addSubview)
        [title, laterButton, rechargeButton].forEach(card.addSubview)
        configureLayout()
        laterButton.nextKeyView = rechargeButton
        rechargeButton.nextKeyView = laterButton
        setAccessibilityRole(.group)
        setAccessibilityChildren([card])
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Fades in using the shared interaction timing and focuses the primary action.
    func present() {
        ControlMotion.setOpacity(
            1,
            on: self,
            from: 0
        )
        focus()
    }

    /// Focuses the primary action within the dialog's two-button key loop.
    func focus() {
        guard !isDismissing else { return }
        window?.makeFirstResponder(rechargeButton)
    }

    /// Blocks further interaction until the fade completes or lifecycle cleanup removes the view.
    func dismiss(
        animated: Bool,
        completion: @escaping @MainActor () -> Void
    ) {
        guard !isDismissing || !animated else { return }
        dismissalTask?.cancel()
        dismissalTask = nil
        isDismissing = true
        window?.makeFirstResponder(self)
        guard animated, ControlMotion.isAnimated(in: self) else {
            completion()
            return
        }
        ControlMotion.setOpacity(
            0,
            on: self
        )
        dismissalTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(ControlMotion.duration)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.dismissalTask = nil
            completion()
        }
    }

    /// Cancels the pending removal when the account or application shuts down.
    func shutdown() {
        dismissalTask?.cancel()
        dismissalTask = nil
        onRecharge = nil
        onDismiss = nil
    }

    /// Treats Escape as the secondary choice without opening the recharge page.
    override func cancelOperation(
        _ sender: Any?
    ) {
        if !isDismissing { onDismiss?() }
    }

    /// Prevents covered controls from receiving presses, including during the closing fade.
    override func hitTest(
        _ point: NSPoint
    ) -> NSView? {
        guard !isHidden, bounds.contains(convert(point, from: superview)) else { return nil }
        return isDismissing ? self : super.hitTest(point) ?? self
    }

    /// Keeps empty-area presses inside the overlay.
    override func mouseDown(
        with event: NSEvent
    ) {}

    /// Keeps empty-area releases inside the overlay.
    override func mouseUp(
        with event: NSEvent
    ) {}

    /// Prevents whitespace drags from reaching the covered page.
    override func mouseDragged(
        with event: NSEvent
    ) {}

    /// Blocks force-click actions on covered links.
    override func pressureChange(
        with event: NSEvent
    ) {}

    /// Keeps the home page stationary while the dialog is visible.
    override func scrollWheel(
        with event: NSEvent
    ) {}

    /// Centers the compact card and gives the two actions equal widths and a shared baseline.
    private func configureLayout() {
        backdrop.snp.makeConstraints { make in make.edges.equalToSuperview() }
        card.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(420).priority(490)
            make.width.lessThanOrEqualToSuperview().offset(-48).priority(490)
            make.width.lessThanOrEqualTo(420)
        }
        title.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(32)
            make.leading.trailing.equalToSuperview().inset(36)
        }
        laterButton.snp.makeConstraints { make in
            make.top.equalTo(title.snp.bottom).offset(28)
            make.leading.equalToSuperview().offset(36)
            make.bottom.equalToSuperview().inset(24)
            make.height.equalTo(44)
        }
        rechargeButton.snp.makeConstraints { make in
            make.leading.equalTo(laterButton.snp.trailing).offset(12)
            make.trailing.equalToSuperview().inset(36)
            make.top.bottom.width.equalTo(laterButton)
        }
    }
}
