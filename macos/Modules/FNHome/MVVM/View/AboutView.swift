//
//  AboutView.swift
//  FaceNow
//

import AppKit
import SnapKit

/// Presents the company, model advantages, and commercial contact in one scrolling modal.
@MainActor
final class AboutView: Canvas {

    /// Routes dismissal and explicit contact outside the content view.
    var onDismiss: (() -> Void)?

    /// Requests the product contact page from the host.
    var onContact: (() -> Void)?

    /// Supplies the static card presentation without retaining business state in controls.
    private let viewModel: AboutViewModel

    /// Prevents click-through during both normal presentation and animated dismissal.
    private var isDismissing = false

    /// Keeps paragraph changes from imposing a new minimum size on the host window.
    private var cardWidth: CGFloat = 980

    /// The backdrop matches onboarding and independently fades behind the white surface.
    private lazy var backdrop: Canvas = {
        let view = Canvas(color: .black.withAlphaComponent(0.35))
        view.setAccessibilityElement(false)
        view.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(dismissFromBackdrop)))
        return view
    }()

    /// Matches onboarding's card corners, elevation, and accessibility modality.
    private lazy var card: Canvas = {
        let view = Canvas(
            color: .white,
            radius: 22
        )
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowOpacity = 0.16
        view.layer?.shadowRadius = 28
        view.layer?.shadowOffset = CGSize(
            width: 0,
            height: -8
        )
        view.setAccessibilityRole(.group)
        view.setAccessibilityModal(true)
        view.setAccessibilityLabel(HomeStrings.aboutUs)
        return view
    }()

    /// Uses onboarding's close affordance and Escape behavior.
    private lazy var closeButton: Button = {
        let view = Button(style: .plain)
        view.symbolName = "xmark"
        view.centersSymbolVisually = true
        view.iconSize = 16
        view.foregroundColor = Palette.secondary
        view.hoverBackgroundColor = Palette.surface
        view.cornerRadius = 8
        view.showsShadow = false
        view.setAccessibilityLabel(HomeStrings.aboutClose)
        view.keyEquivalent = "\u{1b}"
        view.keyEquivalentModifierMask = []
        view.onClick = { [weak self] in self?.onDismiss?() }
        return view
    }()

    /// Preserves all three content sections on shorter windows.
    private lazy var scroll: NSScrollView = {
        let view = NSScrollView()
        view.drawsBackground = false
        view.hasVerticalScroller = true
        view.autohidesScrollers = true
        view.scrollerStyle = .overlay
        return view
    }()

    /// Gives the native document a top-left origin so the introduction appears first.
    private lazy var document: Canvas = {
        let view = Canvas()
        return view
    }()

    /// The three stacked content sections share a single content edge.
    private lazy var content: NSStackView = {
        let view = NSStackView()
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 28
        return view
    }()

    /// Introduces the company and preserves the full model description supplied by the product owner.
    private lazy var introduction: NSStackView = {
        let view = NSStackView()
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 12
        let title = aboutParagraph(
            HomeStrings.aboutModelTitle,
            size: 28,
            weight: .semibold
        )
        let description = aboutParagraph(
            HomeStrings.aboutModelIntroduction,
            size: 15,
            color: Palette.secondary
        )
        for item in [title, description] {
            view.addArrangedSubview(item)
            item.snp.makeConstraints { make in make.width.equalTo(view) }
        }
        view.setCustomSpacing(18, after: title)
        return view
    }()

    /// Summarizes latency, deployment cost, and fidelity as three equal-width cards.
    private lazy var advantages: NSStackView = {
        let view = NSStackView()
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 14
        let title = aboutParagraph(
            HomeStrings.aboutAdvantagesTitle,
            size: 18,
            weight: .semibold
        )
        let row = Canvas()
        let cards = viewModel.advantages.map { AboutAdvantageView(advantage: $0) }
        for (index, card) in cards.enumerated() {
            row.addSubview(card)
            card.snp.makeConstraints { make in
                make.top.bottom.equalToSuperview()
                if index == 0 {
                    make.leading.equalToSuperview()
                } else {
                    make.leading.equalTo(cards[index - 1].snp.trailing).offset(12)
                    make.width.equalTo(cards[0])
                }
                if index == cards.count - 1 { make.trailing.equalToSuperview() }
            }
        }
        [title, row].forEach {
            view.addArrangedSubview($0)
            $0.snp.makeConstraints { make in make.width.equalTo(view) }
        }
        return view
    }()

    /// Connects the virtual-camera app to broader commercial uses with one explicit contact action.
    private lazy var partnership: Canvas = {
        let view = Canvas(
            color: Palette.accent.withAlphaComponent(0.035),
            radius: 18
        )
        let title = aboutParagraph(
            HomeStrings.aboutPartnershipTitle,
            size: 21,
            weight: .semibold
        )
        let description = aboutParagraph(
            HomeStrings.aboutPartnershipDetail,
            size: 15,
            color: Palette.secondary
        )
        let caption = aboutParagraph(
            HomeStrings.aboutContactDetail,
            size: 12,
            color: Palette.secondary
        )
        [title, description, caption, contactButton].forEach { view.addSubview($0) }
        title.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview().inset(22)
        }
        description.snp.makeConstraints { make in
            make.leading.trailing.equalTo(title)
            make.top.equalTo(title.snp.bottom).offset(12)
        }
        contactButton.snp.makeConstraints { make in
            make.leading.bottom.equalToSuperview().inset(22)
            make.top.equalTo(description.snp.bottom).offset(20)
            make.width.equalTo(contactButton.preferredWidth)
            make.height.equalTo(40)
        }
        caption.snp.makeConstraints { make in
            make.leading.equalTo(contactButton.snp.trailing).offset(14)
            make.trailing.equalTo(title)
            make.centerY.equalTo(contactButton)
        }
        return view
    }()

    /// Opens the existing contact email only after an explicit user click.
    private lazy var contactButton: Button = {
        let view = Button(
            HomeStrings.aboutContactUs,
            style: .primary
        )
        view.font = Typography.font(
            size: 13,
            weight: .medium
        )
        view.cornerRadius = 10
        view.showsShadow = false
        view.leadingPadding = 18
        view.trailingPadding = 18
        view.onClick = { [weak self] in self?.onContact?() }
        return view
    }()

    /// Allows the overlay itself to consume events while its closing animation runs.
    override var acceptsFirstResponder: Bool { true }

    /// Creates static content without opening a URL or requesting any camera or account operation.
    init(
        viewModel: AboutViewModel
    ) {
        self.viewModel = viewModel
        super.init()
        [backdrop, card].forEach(addSubview)
        [scroll, closeButton].forEach(card.addSubview)
        scroll.documentView = document
        document.addSubview(content)
        [introduction, advantages, partnership].forEach {
            content.addArrangedSubview($0)
            $0.snp.makeConstraints { make in make.width.equalTo(content) }
        }
        configureLayout()
        backdrop.layer?.opacity = 0
        card.layer?.opacity = 0
        closeButton.nextKeyView = contactButton
        contactButton.nextKeyView = closeButton
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Sizes the card from the viewport, independently of the paragraph's natural width.
    override func layout() {
        let width = min(980, max(0, bounds.width - 64))
        if bounds.width > 0, cardWidth != width {
            cardWidth = width
            card.snp.updateConstraints { make in make.width.equalTo(width) }
        }
        super.layout()
    }

    /// Moves keyboard focus into the modal's closed navigation cycle.
    func focus() { window?.makeFirstResponder(closeButton) }

    /// Uses exactly the same fade, vertical travel, and timing as onboarding.
    func animatePresentation(
        visible: Bool
    ) {
        isDismissing = !visible
        if isDismissing { window?.makeFirstResponder(self) }
        ControlMotion.setModalVisible(
            visible,
            backdrop: backdrop,
            card: card,
            in: self
        ) {
            card.snp.updateConstraints { make in make.centerY.equalToSuperview().offset(visible ? 0 : 24) }
        }
    }

    /// Escape follows the same animated dismissal as the visible close button.
    override func cancelOperation(
        _ sender: Any?
    ) {
        if !isDismissing { onDismiss?() }
    }

    /// Covers modal whitespace and all exit frames instead of forwarding clicks to home links.
    override func hitTest(
        _ point: NSPoint
    ) -> NSView? {
        guard !isHidden, bounds.contains(convert(point, from: superview)) else { return nil }
        return isDismissing ? self : super.hitTest(point) ?? self
    }

    /// Keeps blank-area presses inside the modal.
    override func mouseDown(
        with event: NSEvent
    ) {}

    /// Keeps blank-area releases inside the modal.
    override func mouseUp(
        with event: NSEvent
    ) {}

    /// Prevents modal whitespace drags from reaching the home page.
    override func mouseDragged(
        with event: NSEvent
    ) {}

    /// Blocks force-click previews on the covered home links.
    override func pressureChange(
        with event: NSEvent
    ) {}

    /// Consumes scroll events not handled by the modal's own scrolling document.
    override func scrollWheel(
        with event: NSEvent
    ) {}

    /// Routes only clicks on the backdrop through the modal coordinator.
    @objc private func dismissFromBackdrop() {
        if !isDismissing { onDismiss?() }
    }

    /// Fits the card to its document while letting viewport limits keep long content scrollable.
    private func configureLayout() {
        backdrop.snp.makeConstraints { make in make.edges.equalToSuperview() }
        card.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(24)
            make.width.equalTo(980)
            make.height.equalTo(document.snp.height).offset(60).priority(489)
            make.height.lessThanOrEqualToSuperview().offset(-64).priority(490)
            make.height.lessThanOrEqualTo(760)
        }
        closeButton.snp.makeConstraints { make in
            make.trailing.top.equalToSuperview().inset(22)
            make.size.equalTo(32)
        }
        scroll.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(28)
            make.top.equalToSuperview().inset(32)
            make.bottom.equalToSuperview().inset(28)
        }
        document.snp.makeConstraints { make in
            make.leading.top.equalTo(scroll.contentView)
            make.width.equalTo(scroll.contentView)
        }
        content.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}

/// Uses identical content rows and shared grid edges for each product advantage.
@MainActor
private final class AboutAdvantageView: Canvas {

    /// Retains only the static presentation supplied by the About view model.
    private let advantage: AboutViewModel.Advantage

    /// A restrained accent tile replaces the large orange decorative symbol.
    private lazy var badge: Canvas = {
        let view = Canvas(
            color: Palette.accent.withAlphaComponent(0.06),
            radius: 9
        )
        return view
    }()

    /// Shares one symbol size and optical container across all three cards.
    private lazy var icon: NSImageView = {
        let view = NSImageView()
        view.image = NSImage(
            systemSymbolName: advantage.symbol,
            accessibilityDescription: nil
        )
        view.contentTintColor = Palette.accent
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityElement(false)
        return view
    }()

    /// Keeps all category headings on the same single-line header row.
    private lazy var title: NSTextField = {
        let view = makeLabel(
            advantage.title,
            size: 14,
            color: Palette.secondary,
            weight: .medium
        )
        return view
    }()

    /// Gives every key figure the same font, row height, and baseline position.
    private lazy var metric: NSTextField = {
        let view = makeLabel(
            advantage.metric,
            size: 30,
            weight: .semibold
        )
        return view
    }()

    /// Supporting copy begins at a shared vertical offset and grows only downwards.
    private lazy var detail: NSTextField = {
        let view = aboutParagraph(
            advantage.detail,
            size: 13,
            color: Palette.secondary
        )
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        view.attributedStringValue = NSAttributedString(
            string: advantage.detail,
            attributes: [
                .font: Typography.font(size: 13),
                .foregroundColor: Palette.secondary,
                .paragraphStyle: paragraph,
            ]
        )
        return view
    }()

    /// Builds a quiet white card with a fine outline and aligned content rows.
    init(
        advantage: AboutViewModel.Advantage
    ) {
        self.advantage = advantage
        super.init(color: .white, radius: 14)
        layer?.borderWidth = 1
        layer?.borderColor = Palette.border.withAlphaComponent(0.8).cgColor
        [badge, title, metric, detail].forEach(addSubview)
        badge.addSubview(icon)
        badge.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(20)
            make.size.equalTo(32)
        }
        icon.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(16)
        }
        title.snp.makeConstraints { make in
            make.leading.equalTo(badge.snp.trailing).offset(10)
            make.trailing.equalToSuperview().inset(20)
            make.centerY.equalTo(badge)
        }
        metric.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(20)
            make.top.equalTo(badge.snp.bottom).offset(16)
            make.height.equalTo(40)
        }
        detail.snp.makeConstraints { make in
            make.leading.trailing.equalTo(metric)
            make.top.equalTo(metric.snp.bottom).offset(12)
            make.bottom.lessThanOrEqualToSuperview().inset(20)
            make.bottom.equalToSuperview().inset(20).priority(249)
        }
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }
}

/// Recomputes native wrapped height at the constrained width instead of clipping long product text.
@MainActor
private final class AboutParagraph: NSTextField {

    /// Updates intrinsic height when the containing section's constrained width changes.
    override func layout() {
        super.layout()
        if bounds.width > 0, preferredMaxLayoutWidth != bounds.width {
            preferredMaxLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }
}

/// Creates intrinsic paragraphs with the app's existing typography and native copy behavior.
@MainActor
private func aboutParagraph(
    _ text: String,
    size: CGFloat,
    color: NSColor = Palette.text,
    weight: NSFont.Weight = .regular
) -> NSTextField {
    let view = AboutParagraph(labelWithString: text)
    view.font = Typography.font(
        size: size,
        weight: weight
    )
    view.textColor = color
    view.maximumNumberOfLines = 0
    view.lineBreakMode = .byWordWrapping
    view.cell?.wraps = true
    view.cell?.usesSingleLineMode = false
    view.cell?.isScrollable = false
    view.setContentCompressionResistancePriority(.required, for: .vertical)
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return view
}
