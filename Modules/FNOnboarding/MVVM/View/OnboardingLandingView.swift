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
import UniformTypeIdentifiers
import XmaxSDK

/// Presents the initial camera-start experience without owning a generation session.
@MainActor
final class OnboardingLandingView: Canvas {

    /// The first-launch content supplied by the module's data boundary.
    @Injected(\.onboardingRepo) private var onboardingRepo: OnboardingRepository

    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    /// Starts capture with the chosen resolution and appearance.
    var onStart: ((RealtimeCameraPreset, GenerationReference) -> Void)?

    /// Reports a reference image that could not be imported or approved.
    var onReferenceImportError: ((String) -> Void)?

    /// Reports the current typed notice action to the home coordinator.
    var onCameraAction: ((CameraNoticeAction) -> Void)?

    /// Opens camera-permission guidance from the physical-input selector.
    var onShowCameraSetup: (() -> Void)?

    /// Opens microphone-permission guidance through the home coordinator.
    var onShowMicrophoneSetup: (() -> Void)?

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

    /// Centers the inputs, appearance selector, and start action.
    private lazy var startControls: NSView = {
        let view = NSView()
        return view
    }()

    /// Maps the visible aspect ratios to the X2.1 camera presets in display order.
    private static let resolutionOptions: [(title: String, preset: RealtimeCameraPreset)] = [
        ("16:9", .resolution1920x1080),
        ("9:16", .resolution1080x1920),
        ("1:1", .resolution1408x1408),
        ("3:4", .resolution1152x1536),
        ("4:3", .resolution1536x1152),
    ]

    private let referencePresets = GenerationMode.charx.presets
    private var selectedReference: GenerationReference?
    private var importedReference: GenerationReference?
    private var uploadingReference: GenerationReference?
    private var referenceImport: Task<Void, Never>?
    private var isStarting = false

    /// Keeps the selected appearance beside the independently scrolling list.
    private lazy var appearancePicker: NSView = {
        let view = NSView()
        [previewImage, previewUpload, appearanceDivider, referenceList].forEach { view.addSubview($0) }
        return view
    }()

    private lazy var appearanceDivider: Canvas = {
        let view = Canvas(color: .white.withAlphaComponent(0.25))
        view.setAccessibilityElement(false)
        return view
    }()

    private lazy var previewImage: GenerationThumbnailView = {
        let view = GenerationThumbnailView()
        return view
    }()

    /// Makes the current avatar the upload target.
    private lazy var previewUpload: Button = {
        let view = Button(icon: .plus, style: .plain)
        view.iconSize = 17
        view.foregroundColor = .white
        view.disabledOpacity = 1
        view.backgroundInset = -0.5
        view.restingBackgroundColor = .black.withAlphaComponent(0.42)
        view.hoverBackgroundColor = .black.withAlphaComponent(0.58)
        view.layer?.cornerRadius = GenerationReferenceListView.singleRowAvatarSize / 2
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.55).cgColor
        view.toolTip = GenerationStrings.controlsUploadYourOwnReferenceImage
        view.setAccessibilityLabel(GenerationStrings.controlsUploadYourOwnReferenceImage)
        view.onClick = { [weak self] in self?.chooseReferenceImage() }
        return view
    }()

    private lazy var referenceList: GenerationReferenceListView = {
        let view = GenerationReferenceListView(singleRow: true)
        view.onSelect = { [weak self] reference in self?.selectReference(reference) }
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
        view.loadingOpacity = 0.65
        view.onClick = { [weak self] in
            guard let self, self.referenceImport == nil,
                let index = self.resolutionPicker.selectedIndex, let selectedReference
            else { return }
            self.onStart?(Self.resolutionOptions[index].preset, selectedReference)
        }
        return view
    }()

    /// Selects the physical input beneath the primary capture action.
    private lazy var cameraPicker: HomeInputPickerView = {
        let view = HomeInputPickerView()
        view.onShowCameraSetup = { [weak self] in self?.onShowCameraSetup?() }
        return view
    }()

    /// Selects the system microphone, a named input, or disabled capture before starting.
    private lazy var microphonePicker: HomeInputPickerView = {
        let view = HomeInputPickerView(input: .microphone)
        view.onShowMicrophoneSetup = { [weak self] in self?.onShowMicrophoneSetup?() }
        return view
    }()

    /// Centers both input selectors with consistent spacing beneath the start action.
    private lazy var inputPickers: NSStackView = {
        let view = NSStackView(views: [cameraPicker, microphonePicker])
        view.orientation = .horizontal
        view.alignment = .centerY
        view.spacing = 10
        return view
    }()

    /// Selects one resolution before the camera session starts.
    private lazy var resolutionPicker: TabSwitcher = {
        let view = TabSwitcher(
            titles: Self.resolutionOptions.map { $0.title },
            style: .videoOverlay
        )
        view.horizontalPadding = 12
        for (control, option) in zip(view.selectionControls, Self.resolutionOptions) {
            let size = option.preset.size
            control.toolTip = "\(Int(size.width)) × \(Int(size.height))"
        }
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
        [startControls, serviceNotice].forEach(checkerboard.addSubview)
        [startButton, inputPickers, resolutionPicker, appearancePicker].forEach(startControls.addSubview)
        configureLayout()
        selectReference(referencePresets.first)
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
        let startingChanged = self.isStarting != isStarting
        self.isStarting = isStarting
        startButton.title = isStarting ? OnboardingStrings.landingStarting : OnboardingStrings.landingStartCamera
        startButton.loading = isStarting
        startButton.toolTip = canStart ? OnboardingStrings.landingStartCamera : unavailableMessage
        if startingChanged { updateReferenceSelection() }
        resolutionPicker.isEnabled = !isStarting
        cameraPicker.update()
        microphonePicker.update()
    }

    /// Clears the previous account's images and cancels any pending upload.
    func resetReferenceSelection() {
        referenceImport?.cancel()
        referenceImport = nil
        uploadingReference = nil
        importedReference = nil
        selectReference(referencePresets.first)
    }

    private func selectReference(
        _ reference: GenerationReference?
    ) {
        selectedReference = reference
        updateReferenceSelection()
    }

    private func updateReferenceSelection() {
        let importing = referenceImport != nil
        let enabled = !isStarting && !importing
        let currentUpload = uploadingReference ?? importedReference
        let references = currentUpload.map { [$0] + referencePresets } ?? referencePresets
        referenceList.update(
            references: references,
            selectedID: selectedReference?.id,
            enabled: enabled,
            dimmed: isStarting
        )
        previewImage.configure(selectedReference)
        previewUpload.isEnabled = enabled
        previewUpload.setAccessibilityValue(selectedReference?.name)
        startButton.isEnabled = enabled && selectedReference != nil
    }

    /// Opens the file picker for a single reference image.
    private func chooseReferenceImage() {
        guard !isStarting, referenceImport == nil, let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.importReferenceImage(at: url)
        }
    }

    /// Shows the pending image while the SDK uploads and checks it.
    private func importReferenceImage(
        at url: URL
    ) {
        guard !isStarting, referenceImport == nil else { return }
        referenceImport = Task { [weak self, generationRepo] in
            let result: Result<GenerationReference, Error>
            do {
                var reference = try await Task.detached {
                    try GenerationReference.localImage(
                        at: url,
                        mode: .charx,
                        prompt: GenerationMode.charx.prompt
                    )
                }.value
                try Task.checkCancellation()
                reference.uploadState = .uploading
                self?.uploadingReference = reference
                self?.updateReferenceSelection()
                let id = reference.id
                let approved = try await generationRepo.approveHomeReference(reference) { [weak self] progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in
                        guard let self, var pending = self.uploadingReference,
                            pending.id == id, fraction > pending.uploadProgress
                        else { return }
                        pending.uploadProgress = fraction
                        self.uploadingReference = pending
                        self.updateReferenceSelection()
                    }
                }
                result = .success(approved)
            } catch {
                result = .failure(error)
            }
            guard let self, !Task.isCancelled else { return }
            self.referenceImport = nil
            self.uploadingReference = nil
            switch result {
            case .success(let reference):
                self.importedReference = reference
                self.selectReference(reference)
            case .failure(let error):
                self.updateReferenceSelection()
                self.onReferenceImportError?(error.localizedDescription)
            }
        }
        updateReferenceSelection()
    }

    /// Opens the relocated selector for the shared Choose Camera action.
    func showCameraPicker() { cameraPicker.showPicker() }

    /// Closes native selection before navigation, account changes, or application cleanup.
    func closeCameraPicker() {
        cameraPicker.closePicker()
        microphonePicker.closePicker()
    }

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

    /// Installs the headline, canvas, and centered startup controls once.
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
        startControls.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview().offset(20)
            make.centerY.equalToSuperview().priority(490)
            make.bottom.lessThanOrEqualTo(serviceNotice.snp.top).offset(-12)
        }
        startButton.snp.makeConstraints { make in
            make.centerX.top.equalToSuperview()
            make.width.equalTo(200)
            make.height.equalTo(54)
        }
        inputPickers.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(startButton.snp.bottom).offset(16)
            make.leading.greaterThanOrEqualToSuperview().offset(16)
            make.trailing.lessThanOrEqualToSuperview().inset(16)
        }
        resolutionPicker.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(inputPickers.snp.bottom).offset(14)
            make.leading.greaterThanOrEqualToSuperview().offset(16)
            make.trailing.lessThanOrEqualToSuperview().inset(16)
            make.width.equalTo(resolutionPicker.preferredWidth).priority(490)
            make.height.equalTo(34)
        }
        configureAppearanceLayout()
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

    private func configureAppearanceLayout() {
        let dividerSpacing: CGFloat = 12
        let dividerWidth: CGFloat = 1
        let previewWidth = GenerationReferenceListView.singleRowAvatarSize
        let listWidth = GenerationReferenceListView.singleRowWidth(itemCount: 7)
        appearancePicker.snp.makeConstraints { make in
            make.centerX.bottom.equalToSuperview()
            make.top.equalTo(resolutionPicker.snp.bottom).offset(16)
            make.leading.greaterThanOrEqualToSuperview().offset(24)
            make.trailing.lessThanOrEqualToSuperview().inset(24)
            make.width.equalTo(previewWidth + dividerSpacing * 2 + dividerWidth + listWidth).priority(490)
            make.height.equalTo(GenerationReferenceListView.singleRowHeight)
        }
        previewImage.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
            make.size.equalTo(previewWidth)
        }
        previewUpload.snp.makeConstraints { make in
            make.edges.equalTo(previewImage)
        }
        appearanceDivider.snp.makeConstraints { make in
            make.leading.equalTo(previewImage.snp.trailing).offset(dividerSpacing)
            make.centerY.equalToSuperview()
            make.width.equalTo(dividerWidth)
            make.height.equalTo(32)
        }
        referenceList.snp.makeConstraints { make in
            make.leading.equalTo(appearanceDivider.snp.trailing).offset(dividerSpacing)
            make.trailing.top.bottom.equalToSuperview()
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

    /// Measures the stable-width start button and the linked service notice.
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
        startButton.trailingPadding = min(40, max(25, width * 0.0075 + 18))
        startButton.leadingPadding = startButton.trailingPadding - 2
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
