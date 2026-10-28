//
//  OnboardingLandingView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Factory
import AppKit

/// Presents the initial camera-start experience without owning a generation session.
@MainActor
final class OnboardingLandingView: Canvas {

    /// The first-launch content supplied by the module's data boundary.
    @Injected(\.onboardingRepo) private var onboardingRepo: OnboardingRepository

    /// Notifies the home coordinator of an explicit Start click.
    var onStart: (() -> Void)?

    /// The scroll viewport width used for responsive typography and spacing.
    var viewportWidth: CGFloat = 1360 { didSet { needsLayout = true } }

    /// The product headline displayed above the preview placeholder.
    private lazy var titleLabel: NSTextField = {
        let view = makeLabel(
            onboardingRepo.headline,
            size: 32,
            weight: .medium
        )
        view.alignment = .center
        return view
    }()

    /// The placeholder canvas containing the start action and legal links.
    private lazy var checkerboard: OnboardingCheckerboardView = {
        let view = OnboardingCheckerboardView()
        return view
    }()

    /// Requests capture after the coordinator validates extension readiness.
    private lazy var startButton: Button = {
        let view = Button(
            "Start Camera",
            icon: .camera,
            style: .primary
        )
        view.iconSize = 20
        view.iconSpacing = 10
        view.onClick = { [weak self] in self?.onStart?() }
        return view
    }()

    /// The native text view retaining selectable terms and privacy links.
    private lazy var terms: NSTextView = {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.linkTextAttributes = [
            .foregroundColor: NSColor(
                srgbRed: 0.765,
                green: 0.776,
                blue: 0.8,
                alpha: 1
            )
        ]
        return view
    }()

    /// The copyright line below the start canvas.
    private lazy var copyright: NSTextField = {
        let view = makeLabel(
            onboardingRepo.copyright,
            size: 13,
            color: Palette.secondary
        )
        view.alignment = .center
        return view
    }()

    /// Composes the startup view from its configured native controls.
    init() {
        super.init()
        [titleLabel, checkerboard, copyright].forEach(addSubview)
        [startButton, terms].forEach(checkerboard.addSubview)
    }

    /// Storyboard decoding is unsupported for this programmatic view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Measures the headline, video-shaped placeholder, and copyright line.
    func preferredHeight(
        contentWidth: CGFloat
    ) -> CGFloat {
        let titleSize = min(45, max(27, viewportWidth * 0.01 + 18))
        let titleGap = min(40, max(26, viewportWidth * 0.011 + 17))
        let titleHeight = ceil(
            Typography.size(
                titleLabel.stringValue,
                font: Typography.font(
                    size: titleSize,
                    weight: .medium
                )
            ).height
        )
        copyright.font = Typography.font(size: min(14, max(11.5, viewportWidth * 0.0028 + 9)))
        let copyrightHeight = ceil(
            Typography.size(
                copyright.stringValue,
                font: copyright.font!
            ).height
        )
        let stageWidth = min(contentWidth, min(940, max(580, viewportWidth * 0.45)))
        let stageHeight =
            stageWidth * CGFloat(VirtualCameraConfiguration.height) / CGFloat(VirtualCameraConfiguration.width)
        return titleHeight + titleGap + stageHeight + 16 + copyrightHeight
    }

    /// Reflects start availability without creating or opening a capture device.
    func update(
        isStarting: Bool,
        canStart: Bool,
        unavailableMessage: String
    ) {
        startButton.title = isStarting ? "Starting…" : "Start Camera"
        startButton.loading = isStarting
        startButton.isEnabled = !isStarting && canStart
        startButton.toolTip = canStart ? "Start Camera" : unavailableMessage
    }

    /// Arranges the startup controls using the shared media aspect ratio.
    override func layout() {
        super.layout()
        let titleSize = min(45, max(27, viewportWidth * 0.01 + 18))
        let titleGap = min(40, max(26, viewportWidth * 0.011 + 17))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        titleLabel.attributedStringValue = NSAttributedString(
            string: onboardingRepo.headline,
            attributes: [
                .font: Typography.font(
                    size: titleSize,
                    weight: .medium
                ),
                .foregroundColor: Palette.text, .kern: -titleSize * 0.03, .paragraphStyle: paragraph,
            ]
        )
        let titleHeight = ceil(
            Typography.size(
                titleLabel.stringValue,
                font: Typography.font(
                    size: titleSize,
                    weight: .medium
                )
            ).height
        )
        let stageWidth = min(bounds.width, min(940, max(580, viewportWidth * 0.45)))
        let stageHeight =
            stageWidth * CGFloat(VirtualCameraConfiguration.height) / CGFloat(VirtualCameraConfiguration.width)
        titleLabel.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: titleHeight
        )
        checkerboard.frame = NSRect(
            x: (bounds.width - stageWidth) / 2,
            y: titleHeight + titleGap,
            width: stageWidth,
            height: stageHeight
        )
        layoutStartControls(viewportWidth: viewportWidth)
        let copyrightHeight = ceil(
            Typography.size(
                copyright.stringValue,
                font: copyright.font!
            ).height
        )
        copyright.frame = NSRect(
            x: 0,
            y: checkerboard.frame.maxY + 16,
            width: bounds.width,
            height: copyrightHeight
        )
    }

    /// Centers the stable-width start button and lays out selectable legal links.
    private func layoutStartControls(
        viewportWidth width: CGFloat
    ) {
        let fontSize = min(18, max(15, width * 0.003 + 12))
        let smallSize = min(15, max(12, width * 0.0028 + 9.5))
        startButton.font = Typography.font(
            size: fontSize,
            weight: .semibold
        )
        startButton.leadingPadding = min(40, max(25, width * 0.0075 + 18))
        startButton.trailingPadding = startButton.leadingPadding
        let buttonHeight =
            max(
                20,
                ceil(
                    Typography.size(
                        startButton.title,
                        font: startButton.font!
                    ).height
                )
            ) + min(16, max(12, width * 0.0028 + 9)) * 2
        // Reserve the longest state label so startup never shrinks the button.
        let labelWidth =
            ["Start Camera", "Starting…"].map {
                Typography.size(
                    $0,
                    font: startButton.font!
                ).width
            }.max() ?? 0
        let buttonWidth = ceil(
            labelWidth + startButton.iconSize + startButton.iconSpacing + startButton.leadingPadding
                + startButton.trailingPadding
        )
        startButton.frame = NSRect(
            x: (checkerboard.bounds.width - buttonWidth) / 2,
            y: (checkerboard.bounds.height - buttonHeight) / 2,
            width: buttonWidth,
            height: buttonHeight
        )
        let text = onboardingRepo.agreement
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: Typography.font(size: smallSize), .paragraphStyle: paragraph,
                .foregroundColor: NSColor(
                    srgbRed: 0.612,
                    green: 0.639,
                    blue: 0.686,
                    alpha: 1
                ),
            ]
        )
        attributed.addAttribute(
            .link,
            value: onboardingRepo.termsURL.absoluteString,
            range: (text as NSString).range(of: "Terms of Use")
        )
        attributed.addAttribute(
            .link,
            value: onboardingRepo.privacyURL.absoluteString,
            range: (text as NSString).range(of: "Privacy Policy")
        )
        let termsWidth = checkerboard.bounds.width - 40
        let termsHeight = ceil(
            attributed.boundingRect(
                with: NSSize(
                    width: termsWidth,
                    height: 100
                ),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height
        )
        terms.frame = NSRect(
            x: 20,
            y: checkerboard.bounds.height - 30 - termsHeight,
            width: termsWidth,
            height: termsHeight
        )
        if !terms.attributedString().isEqual(to: attributed) { terms.textStorage?.setAttributedString(attributed) }
    }

}
