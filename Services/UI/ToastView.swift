//
//  ToastView.swift
//  FaceNow
//

import AppKit
import SnapKit

/// Presents selectable success and error notifications without owning business state.
@MainActor
final class ToastView: Canvas {

    /// The semantic appearance of the transient notification.
    enum Style {

        /// A failure requiring the user's attention.
        case error

        /// A successfully completed user action.
        case success
    }

    /// Hides the view only after its fade completes, and is cancelled by a newer message.
    private var dismissal: Task<Void, Never>?

    /// Cancels an older display interval when a new message replaces it.
    private var autoDismissal: Task<Void, Never>?

    /// Avoids restarting display timing during an unchanged host refresh.
    private var displayedMessage: String?

    /// Distinguishes a style change from an unchanged message refresh.
    private var displayedStyle = Style.error

    /// Whether the host placement constraints have been installed.
    private var placementInstalled = false

    /// The resting distance from the top of the hosting content view.
    private static let topInset: CGFloat = 32

    /// The vertical travel shared by downward entrance and upward dismissal.
    private static let entryDistance: CGFloat = 32

    /// The explicitly requested timing for toast movement and fading.
    private static let animationDuration: TimeInterval = 0.4

    /// The layer-local offset above the resting position in the parent's coordinate system.
    private var raisedOffset: CGFloat {
        let flipped = layer?.superlayer?.isGeometryFlipped ?? superview?.isFlipped ?? true
        return flipped ? -Self.entryDistance : Self.entryDistance
    }

    /// The outer padding before the semantic icon.
    private static let leadingInset: CGFloat = 13

    /// The compact outer padding after the dismissal control.
    private static let trailingInset: CGFloat = 9

    /// The gap separating the semantic icon from the message.
    private static let iconSpacing: CGFloat = 9

    /// The compact gap between the message and the dismissal hit area.
    private static let dismissSpacing: CGFloat = 1

    /// The dismissal hit area, independent of its visible symbol size.
    private static let dismissSize: CGFloat = 28

    /// Lets the host clear its business state after manual or automatic dismissal.
    var onDismiss: (() -> Void)?

    /// The error symbol displayed beside the message.
    private lazy var toastIcon: NSImageView = {
        let view = NSImageView()
        view.image = NSImage(
            systemSymbolName: "exclamationmark.circle",
            accessibilityDescription: nil
        )
        view.contentTintColor = .systemRed
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }()

    /// The native selectable message label.
    private lazy var toastMessage: NSTextField = {
        let view = makeLabel(size: 14)
        view.maximumNumberOfLines = 0
        view.lineBreakMode = .byWordWrapping
        view.cell?.usesSingleLineMode = false
        view.cell?.wraps = true
        view.cell?.isScrollable = false
        view.isSelectable = true
        return view
    }()

    /// The explicit dismissal control.
    private lazy var toastDismiss: Button = {
        let view = Button(style: .plain)
        view.symbolName = "xmark"
        view.iconSize = 16
        view.setAccessibilityLabel(
            Localization.string(
                "action.dismiss",
                table: "Common",
                defaultValue: "Dismiss"
            )
        )
        view.onClick = { [weak self] in self?.dismiss() }
        return view
    }()

    /// Creates the persistent notification controls.
    init() {
        super.init(
            color: .white.withAlphaComponent(0.96),
            radius: 14
        )
        isHidden = true

        [toastIcon, toastMessage, toastDismiss].forEach(addSubview)
        toastIcon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.leadingInset)
            make.centerY.equalToSuperview()
            make.size.equalTo(20)
        }
        toastDismiss.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(Self.trailingInset)
            make.centerY.equalToSuperview()
            make.size.equalTo(Self.dismissSize)
        }
        toastMessage.snp.makeConstraints { make in
            make.leading.equalTo(toastIcon.snp.trailing).offset(Self.iconSpacing)
            make.trailing.equalTo(toastDismiss.snp.leading).offset(-Self.dismissSpacing)
            make.centerY.equalToSuperview()
            make.height.equalTo(20)
        }
        layer?.borderWidth = 1
        layer?.borderColor = Palette.text.withAlphaComponent(0.10).cgColor
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.12
        layer?.shadowRadius = 12

        layer?.shadowOffset = CGSize(
            width: 0,
            height: 5
        )
    }

    /// Storyboard decoding is unsupported for this programmatic view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Gives the notification valid dimensions as soon as its host is available.
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let superview else { return }
        place(in: superview.bounds)
    }

    /// Keeps the soft shadow aligned with the rounded surface as wrapped text changes its size.
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: layer?.cornerRadius ?? 14,
            cornerHeight: layer?.cornerRadius ?? 14,
            transform: nil
        )
        CATransaction.commit()
    }

    /// Applies a notification and announces only a newly presented message.
    func update(
        message: String?,
        announce: Bool,
        style: Style = .error,
        duration: TimeInterval? = nil
    ) {
        guard let message else {
            autoDismissal?.cancel()
            autoDismissal = nil
            displayedMessage = nil
            guard !isHidden, dismissal == nil else { return }
            animateVerticalOffset(raisedOffset)
            ControlMotion.setOpacity(
                0,
                on: self,
                duration: Self.animationDuration
            )
            guard ControlMotion.isAnimated(in: self) else {
                isHidden = true
                return
            }
            dismissal = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(Self.animationDuration)) } catch { return }
                self?.isHidden = true
                self?.dismissal = nil
            }
            return
        }
        dismissal?.cancel()
        dismissal = nil
        let changed = message != displayedMessage || style != displayedStyle
        displayedMessage = message
        displayedStyle = style
        toastMessage.stringValue = message
        toastIcon.image = NSImage(
            systemSymbolName: style == .success ? "checkmark.circle.fill" : "exclamationmark.circle",
            accessibilityDescription: nil
        )
        toastIcon.contentTintColor = style == .success ? .systemGreen : .systemRed
        if let superview { place(in: superview.bounds) }
        show()
        if changed || announce {
            autoDismissal?.cancel()
            let interval = duration ?? 4
            autoDismissal = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
                self?.dismiss()
            }
        }
        if announce {
            NSAccessibility.post(
                element: toastMessage,
                notification: .announcementRequested,
                userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue]
            )
        }
    }

    /// Slides a newly visible toast downward while fading in, respecting Reduce Motion.
    private func show() {
        let appearing = isHidden
        if appearing {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            alphaValue = 0
            isHidden = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                superview?.layoutSubtreeIfNeeded()
            }
            CATransaction.commit()
        }
        animateVerticalOffset(
            0,
            from: appearing ? raisedOffset : nil
        )
        ControlMotion.setOpacity(
            1,
            on: self,
            from: appearing ? 0 : nil,
            duration: Self.animationDuration
        )
    }

    /// Retargets only vertical travel from its visible offset when a dismissal is interrupted.
    private func animateVerticalOffset(
        _ offset: CGFloat,
        from initialOffset: CGFloat? = nil
    ) {
        guard let layer else { return }
        let keyPath = "transform.translation.y"
        let current = (layer.value(forKeyPath: keyPath) as? NSNumber)?.doubleValue ?? 0
        guard CGFloat(current) != offset || initialOffset != nil else { return }
        let visible =
            initialOffset
            ?? (layer.presentation()?.value(forKeyPath: keyPath) as? NSNumber).map { CGFloat($0.doubleValue) }
            ?? CGFloat(current)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(offset, forKeyPath: keyPath)
        CATransaction.commit()
        guard ControlMotion.isAnimated(in: self) else {
            layer.removeAnimation(forKey: "toastSlideY")
            return
        }
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = visible
        animation.toValue = offset
        animation.duration = Self.animationDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(
            animation,
            forKey: "toastSlideY"
        )
    }

    /// Hides the notification before notifying the host, including when no callback is installed.
    private func dismiss() {
        guard displayedMessage != nil else { return }
        update(
            message: nil,
            announce: false
        )
        onDismiss?()
    }

    /// Cancels view-bound fading when the owning application shuts down.
    func shutdown() {
        autoDismissal?.cancel()
        autoDismissal = nil
        displayedMessage = nil
        dismissal?.cancel()
        dismissal = nil
        layer?.removeAnimation(forKey: "toastSlideY")
        isHidden = true
    }

    /// Centers the wrapped notification inside the window content.
    func place(
        in contentBounds: NSRect
    ) {
        let accessoryWidth =
            Self.leadingInset + 20 + Self.iconSpacing + Self.dismissSpacing + Self.dismissSize + Self.trailingInset
        let maximumWidth = min(560, max(accessoryWidth + 1, contentBounds.width - 56))
        let naturalTextWidth = ceil(toastMessage.attributedStringValue.size().width) + 4
        let width = min(maximumWidth, naturalTextWidth + accessoryWidth)
        let textWidth = max(1, width - accessoryWidth)
        let textHeight = ceil(
            toastMessage.cell?.cellSize(
                forBounds: NSRect(
                    x: 0,
                    y: 0,
                    width: textWidth,
                    height: .greatestFiniteMagnitude
                )
            ).height ?? 0
        )
        let height = max(48, textHeight + 16)
        if !placementInstalled {
            snp.makeConstraints { make in
                make.centerX.equalToSuperview()
                make.top.equalToSuperview().offset(Self.topInset)
                make.width.equalTo(width)
                make.height.equalTo(height)
            }
            placementInstalled = true
        } else {
            snp.updateConstraints { make in
                make.width.equalTo(width)
                make.height.equalTo(height)
            }
        }
        toastMessage.snp.updateConstraints { make in make.height.equalTo(textHeight) }
    }

}
