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
import AVFoundation

/// Presents the initial camera-start experience without owning a generation session.
@MainActor
final class OnboardingLandingView: Canvas {

    /// The first-launch content supplied by the module's data boundary.
    @Injected(\.onboardingRepo) private var onboardingRepo: OnboardingRepository

    /// Notifies the home coordinator of an explicit Start Camera click.
    var onStart: (() -> Void)?

    /// Reopens preparation from the persistent device-readiness reminder.
    var onSetup: (() -> Void)?

    /// Toggles physical camera preview without entering the generation workspace.
    var onPreview: (() -> Void)?

    /// The live camera surface behind all canvas actions.
    private lazy var cameraPreview: CameraPreviewView = {
        let view = CameraPreviewView()
        view.isHidden = true
        return view
    }()

    /// Dims the full live canvas while leaving its buttons above the overlay.
    private lazy var previewOverlay: Canvas = {
        let view = Canvas(color: .black.withAlphaComponent(0.4))
        view.isHidden = true
        return view
    }()

    /// Offers a secondary, translucent preview action beneath Start Camera.
    private lazy var previewButton: Button = {
        let view = Button("Preview", style: .plain)
        view.font = Typography.font(size: 13, weight: .medium)
        view.foregroundColor = .white
        view.restingBackgroundColor = .black.withAlphaComponent(0.45)
        view.hoverBackgroundColor = .black.withAlphaComponent(0.65)
        view.cornerRadius = 18
        view.showsShadow = false
        view.onClick = { [weak self] in self?.onPreview?() }
        return view
    }()

    /// Keeps missing permissions and unfinished preparation visible after the dialog is deferred.
    private lazy var setupReminder: Button = {
        let view = Button()
        view.font = Typography.font(size: 12)
        view.symbolName = "exclamationmark.circle"
        view.iconSize = 14
        view.showsShadow = false
        view.onClick = { [weak self] in self?.onSetup?() }
        return view
    }()

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

    /// The placeholder canvas containing the start action and preview guidance.
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
        view.disabledOpacity = 1
        view.loadingOpacity = 0.65
        view.onClick = { [weak self] in self?.onStart?() }
        return view
    }()

    /// The selectable guidance beneath the Start Camera action.
    private lazy var previewHint: NSTextView = {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
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
        [cameraPreview, previewOverlay, setupReminder, startButton, previewButton, previewHint]
            .forEach(checkerboard.addSubview)
        configureLayout()
    }

    /// Storyboard decoding is unsupported for this programmatic view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Shares the responsive canvas width between page measurement and actual layout.
    private func preferredStageWidth(
        contentWidth: CGFloat
    ) -> CGFloat {
        min(contentWidth, min(1040, max(640, viewportWidth * 0.55)))
    }

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
        let stageWidth = preferredStageWidth(contentWidth: contentWidth)
        let stageHeight =
            stageWidth * CGFloat(VirtualCameraConfiguration.height) / CGFloat(VirtualCameraConfiguration.width)
        return titleHeight + titleGap + stageHeight + 16 + copyrightHeight
    }

    /// Keeps unavailable starts clickable for coordinator feedback while blocking duplicate startup requests.
    func update(
        isStarting: Bool,
        canStart: Bool,
        unavailableMessage: String
    ) {
        startButton.title = isStarting ? "Starting…" : "Start Camera"
        startButton.loading = isStarting
        startButton.isEnabled = !isStarting
        startButton.toolTip = canStart ? "Start Camera" : unavailableMessage
    }

    /// Reflects live device preparation without dismissing the reminder on a timer.
    func updatePreparation(
        model: OnboardingFlowViewModel
    ) {
        setupReminder.title = model.reminder
        setupReminder.toolTip = model.reminder
        let ready = model.cameraReady && model.virtualCameraReady
        setupReminder.symbolName = ready ? "checkmark.circle" : "exclamationmark.circle"
        setupReminder.foregroundColor = !model.cameraReady ? .systemRed : ready ? .systemGreen : .systemOrange
    }

    /// Binds the local capture surface and reflects only the preview toggle's state.
    func updatePreview(
        session: AVCaptureSession,
        isPreviewing: Bool,
        isLoading: Bool,
        isAvailable: Bool
    ) {
        cameraPreview.bind(session: session)
        cameraPreview.isHidden = !isPreviewing
        previewOverlay.isHidden = !isPreviewing
        previewButton.loading = isLoading
        previewButton.isEnabled = isAvailable && !isLoading
        previewButton.toolTip = isPreviewing ? "Close camera preview" : "Open camera preview"
        previewButton.setAccessibilityValue(isPreviewing ? "On" : "Off")
    }

    /// Installs the headline, ratio-constrained canvas, and centered startup controls once.
    private func configureLayout() {
        cameraPreview.snp.makeConstraints { make in make.edges.equalToSuperview() }
        previewOverlay.snp.makeConstraints { make in make.edges.equalToSuperview() }
        previewButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(startButton.snp.bottom).offset(12)
            make.width.equalTo(112)
            make.height.equalTo(36)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
            make.height.equalTo(40)
        }
        checkerboard.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(32)
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
        setupReminder.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.top.equalToSuperview().offset(14)
            make.height.equalTo(34)
        }
        previewHint.snp.makeConstraints { make in
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
        let stageWidth = preferredStageWidth(contentWidth: bounds.width)
        titleLabel.snp.updateConstraints { make in make.height.equalTo(titleHeight) }
        checkerboard.snp.updateConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(titleGap)
            make.width.equalTo(stageWidth)
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

    /// Centers the stable-width start button and lays out selectable preview guidance.
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
        startButton.snp.updateConstraints { make in
            make.width.equalTo(buttonWidth)
            make.height.equalTo(buttonHeight)
        }
        let text = onboardingRepo.previewHint
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributed = NSAttributedString(
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
        previewHint.snp.updateConstraints { make in make.height.equalTo(hintHeight) }
        if !previewHint.attributedString().isEqual(to: attributed) {
            previewHint.textStorage?.setAttributedString(attributed)
        }
    }

}
