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
import SnapKit

/// Presents the initial camera-start experience without owning a generation session.
@MainActor
final class OnboardingLandingView: Canvas {

    /// The first-launch content supplied by the module's data boundary.
    @Injected(\.onboardingRepo) private var onboardingRepo: OnboardingRepository

    /// Notifies the home coordinator of an explicit Start Camera click.
    var onStart: (() -> Void)?

    /// Reports the current typed notice action to the home coordinator.
    var onCameraAction: ((CameraNoticeAction) -> Void)?

    /// Opens camera-permission guidance from the physical-input selector.
    var onShowCameraSetup: (() -> Void)?

    /// Shows confirmed permission or device failures above the camera canvas.
    private lazy var setupReminder: CameraStatusBannerView = {
        let view = CameraStatusBannerView()
        view.onAction = { [weak self] action in self?.onCameraAction?(action) }
        return view
    }()

    /// Positions the canvas directly after the headline when no warning is present.
    private var normalCanvasTop: Constraint?

    /// Positions the canvas after the persistent warning while preparation is blocked.
    private var warningCanvasTop: Constraint?

    /// The scroll viewport width used for responsive typography and spacing.
    var viewportWidth: CGFloat = 1360 { didSet { needsLayout = true } }

    /// The product headline displayed above the startup canvas.
    private lazy var titleLabel: NSTextField = {
        let view = makeLabel(
            onboardingRepo.headline,
            size: 32,
            weight: .medium
        )
        view.alignment = .center
        return view
    }()

    /// The startup canvas containing capture controls and the service notice.
    private lazy var checkerboard: OnboardingCheckerboardView = {
        let view = OnboardingCheckerboardView()
        return view
    }()

    /// Requests capture after the coordinator validates extension readiness.
    private lazy var startButton: Button = {
        let view = Button(
            OnboardingStrings.landingStartCamera,
            icon: .camera,
            style: .primary
        )
        view.iconSize = 20
        view.iconSpacing = 10
        view.centersTitleVisually = true
        view.disabledOpacity = 1
        view.loadingOpacity = 0.65
        view.onClick = { [weak self] in self?.onStart?() }
        return view
    }()

    /// Selects the physical input beneath the primary capture action.
    private lazy var cameraPicker: HomeCameraPickerView = {
        let view = HomeCameraPickerView()
        view.onShowCameraSetup = { [weak self] in self?.onShowCameraSetup?() }
        return view
    }()

    /// The selectable service notice with independent terms and privacy links.
    private lazy var serviceNotice: NSTextView = {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        #if OVERSEA
            let underlineStyle = NSUnderlineStyle.single.rawValue
        #else
            let underlineStyle = 0
        #endif
        view.linkTextAttributes = [
            .foregroundColor: NSColor(
                srgbRed: 0.765,
                green: 0.776,
                blue: 0.8,
                alpha: 1
            ),
            .underlineStyle: underlineStyle,
            .cursor: NSCursor.pointingHand,
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
        [titleLabel, setupReminder, checkerboard, copyright].forEach(addSubview)
        [startButton, cameraPicker, serviceNotice].forEach(checkerboard.addSubview)
        configureLayout()
    }

    /// Storyboard decoding is unsupported for this programmatic view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Suspends native link activation and pressure previews while the setup overlay covers the page.
    func setServiceNoticeInteractionEnabled(
        _ enabled: Bool
    ) {
        guard serviceNotice.isSelectable != enabled else { return }
        serviceNotice.isSelectable = enabled
    }

    /// Shares the responsive canvas width between page measurement and actual layout.
    private func preferredStageWidth(
        contentWidth: CGFloat
    ) -> CGFloat {
        min(contentWidth, min(1040, max(640, viewportWidth * 0.55)))
    }

    /// Keeps a visible preparation notice close to the headline in both layout and measurement.
    private var headlineGap: CGFloat {
        if !setupReminder.isHidden {
            return min(24, max(16, viewportWidth * 0.006 + 10))
        }
        return min(40, max(26, viewportWidth * 0.011 + 17))
    }

    /// Measures the headline, video-shaped placeholder, and copyright line.
    func preferredHeight(
        contentWidth: CGFloat
    ) -> CGFloat {
        let titleSize = min(45, max(27, viewportWidth * 0.01 + 18))
        let titleGap = headlineGap
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
        let stageWidth = preferredStageWidth(contentWidth: contentWidth)
        let stageHeight =
            stageWidth * CGFloat(VirtualCameraConfiguration.height) / CGFloat(VirtualCameraConfiguration.width)
        let warningHeight = setupReminder.preferredHeight(width: stageWidth)
        return titleHeight + titleGap + (warningHeight > 0 ? warningHeight + 12 : 0)
            + stageHeight + 16 + copyrightHeight
    }

    /// Keeps unavailable starts clickable for coordinator feedback while blocking duplicate startup requests.
    func update(
        isStarting: Bool,
        canStart: Bool,
        unavailableMessage: String
    ) {
        startButton.title = isStarting ? OnboardingStrings.landingStarting : OnboardingStrings.landingStartCamera
        startButton.loading = isStarting
        startButton.isEnabled = !isStarting
        startButton.toolTip = canStart ? OnboardingStrings.landingStartCamera : unavailableMessage
        cameraPicker.update()
    }

    /// Opens the relocated selector for the shared Choose Camera action.
    func showCameraPicker() { cameraPicker.showCameraPicker() }

    /// Closes native selection before navigation, account changes, or application cleanup.
    func closeCameraPicker() { cameraPicker.closeCameraPicker() }

    /// Shows a persistent reason only for denied permissions or confirmed device unavailability.
    func updatePreparation(
        presentation: CameraNoticePresentation?
    ) {
        guard setupReminder.update(presentation: presentation) else { return }
        if presentation == nil {
            warningCanvasTop?.deactivate()
            normalCanvasTop?.activate()
        } else {
            normalCanvasTop?.deactivate()
            warningCanvasTop?.activate()
        }
        needsLayout = true
    }

    /// Installs the headline, ratio-constrained canvas, and centered startup controls once.
    private func configureLayout() {
        titleLabel.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
            make.height.equalTo(40)
        }
        checkerboard.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            normalCanvasTop = make.top.equalTo(titleLabel.snp.bottom).offset(32).constraint
            make.width.equalTo(640)
            make.height.equalTo(checkerboard.snp.width).multipliedBy(
                CGFloat(VirtualCameraConfiguration.height) / CGFloat(VirtualCameraConfiguration.width)
            )
        }
        copyright.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(checkerboard.snp.bottom).offset(16)
            make.height.equalTo(18)
        }
        startButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(200)
            make.height.equalTo(54)
        }
        cameraPicker.snp.makeConstraints { make in
            make.centerX.equalTo(startButton)
            make.top.equalTo(startButton.snp.bottom).offset(12)
        }
        setupReminder.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(32)
            make.width.equalTo(640)
            make.height.equalTo(44)
        }
        checkerboard.snp.prepareConstraints { make in
            warningCanvasTop = make.top.equalTo(setupReminder.snp.bottom).offset(12).constraint
        }
        serviceNotice.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(20)
            make.bottom.equalToSuperview().inset(30)
            make.height.equalTo(20)
        }
    }

    /// Arranges the startup controls using the shared media aspect ratio.
    override func layout() {
        guard bounds.width > 40 else {
            super.layout()
            return
        }
        let titleSize = min(45, max(27, viewportWidth * 0.01 + 18))
        let titleGap = headlineGap
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
        let stageWidth = preferredStageWidth(contentWidth: bounds.width)
        titleLabel.snp.updateConstraints { make in make.height.equalTo(titleHeight) }
        normalCanvasTop?.update(offset: titleGap)
        checkerboard.snp.updateConstraints { make in make.width.equalTo(stageWidth) }
        setupReminder.snp.updateConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(titleGap)
            make.width.equalTo(stageWidth)
            make.height.equalTo(max(44, setupReminder.preferredHeight(width: stageWidth)))
        }
        layoutStartControls(
            viewportWidth: viewportWidth,
            stageWidth: stageWidth
        )
        let copyrightHeight = ceil(
            Typography.size(
                copyright.stringValue,
                font: copyright.font!
            ).height
        )
        copyright.snp.updateConstraints { make in make.height.equalTo(copyrightHeight) }
        // Resolve the canvas and its children together using the current viewport dimensions.
        super.layout()
    }

    /// Centers the stable-width start button and lays out the linked service notice.
    private func layoutStartControls(
        viewportWidth width: CGFloat,
        stageWidth: CGFloat
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
            [OnboardingStrings.landingStartCamera, OnboardingStrings.landingStarting].map {
                Typography.size(
                    $0,
                    font: startButton.font!
                ).width
            }.max() ?? 0
        let buttonWidth = ceil(
            labelWidth + startButton.iconSize + startButton.iconSpacing + startButton.leadingPadding
                + startButton.trailingPadding
        )
        startButton.snp.updateConstraints { make in
            make.width.equalTo(buttonWidth)
            make.height.equalTo(buttonHeight)
        }
        let text = onboardingRepo.serviceNotice
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
            value: onboardingRepo.termsURL,
            range: serviceNoticeLinkRange(OnboardingStrings.termsOfUse, in: text)
        )
        attributed.addAttribute(
            .link,
            value: onboardingRepo.privacyURL,
            range: serviceNoticeLinkRange(OnboardingStrings.privacyPolicy, in: text)
        )
        let hintWidth = max(1, stageWidth - 40)
        let hintHeight = ceil(
            attributed.boundingRect(
                with: NSSize(
                    width: hintWidth,
                    height: 100
                ),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height
        )
        serviceNotice.snp.updateConstraints { make in make.height.equalTo(hintHeight) }
        if !serviceNotice.attributedString().isEqual(to: attributed) {
            serviceNotice.textStorage?.setAttributedString(attributed)
        }
    }

    /// Includes Chinese book-title marks in each document's link appearance and click target.
    private func serviceNoticeLinkRange(
        _ title: String,
        in text: String
    ) -> NSRange {
        let value = text as NSString
        let wrappedRange = value.range(of: "《\(title)》")
        return wrappedRange.location == NSNotFound ? value.range(of: title) : wrappedRange
    }

}
