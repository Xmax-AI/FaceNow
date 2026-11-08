//
//  VideoCallsGuideView.swift
//  FaceNow
//

import AppKit
import SnapKit

/// Presents the original Lark, Tencent Meeting, and WeChat examples with named pagination.
@MainActor
final class VideoCallsGuideView: Canvas {

    /// Exposes only the currently visible carousel's native controls to the modal focus cycle.
    var navigationControls: [NSControl] { [previousPage] + pageDots + [nextPage] }

    /// Keeps manual browsing local to this view instead of changing preparation or app settings.
    private var selectedPage: Int?

    /// The fixed order matches the three screenshot examples supplied by the user.
    private let guides = VideoCallGuide.allCases

    /// Retains all originals so page switches can cross-fade without cropping or reloading assets.
    private lazy var images: [NSImageView] = {
        guides.map { guide in
            let view = NSImageView()
            view.image = NSImage(named: guide.assetName)
            view.imageScaling = .scaleProportionallyUpOrDown
            view.setContentCompressionResistancePriority(
                .defaultLow,
                for: .horizontal
            )
            view.setContentCompressionResistancePriority(
                .defaultLow,
                for: .vertical
            )
            view.wantsLayer = true
            view.alphaValue = 0
            view.setAccessibilityLabel(OnboardingStrings.videoCallsShowExample(app: guide.name))
            view.setAccessibilityElement(false)
            return view
        }
    }()

    /// Labels each screenshot with its actual video-calling application.
    private lazy var appName: NSTextField = {
        let view = makeLabel(
            size: 14,
            weight: .semibold
        )
        view.alignment = .center
        view.wantsLayer = true
        return view
    }()

    /// Explains the camera-menu action below the original screenshot.
    private lazy var caption: NSTextField = {
        let view = makeLabel(
            size: 12,
            color: Palette.secondary
        )
        view.maximumNumberOfLines = 0
        view.lineBreakMode = .byWordWrapping
        view.cell?.wraps = true
        view.cell?.usesSingleLineMode = false
        view.cell?.isScrollable = false
        view.alignment = .center
        view.setContentCompressionResistancePriority(
            .required,
            for: .vertical
        )
        return view
    }()

    /// Matches the existing virtual-camera walkthrough's centered arrows and page dots.
    private lazy var pagination: NSStackView = {
        let view = NSStackView()
        view.orientation = .horizontal
        view.alignment = .centerY
        view.spacing = 2
        return view
    }()

    /// Wraps to the final example when moving back from Lark.
    private lazy var previousPage: Button = {
        let view = Button(style: .plain)
        view.symbolName = "chevron.left"
        view.iconSize = 12
        view.centersSymbolVisually = true
        view.showsShadow = false
        view.cornerRadius = 14
        view.hoverBackgroundColor = Palette.border.withAlphaComponent(0.5)
        view.setAccessibilityLabel(OnboardingStrings.previousGuideImage)
        view.onClick = { [weak self] in
            guard let self else { return }
            self.selectPage(((self.selectedPage ?? 0) + self.guides.count - 1) % self.guides.count)
        }
        return view
    }()

    /// Each seven-point dot keeps the same larger hit target as the extension walkthrough.
    private lazy var pageDots: [Button] = {
        guides.enumerated().map { index, guide in
            let view = Button(style: .plain)
            view.symbolName = "circle.fill"
            view.iconSize = 7
            view.centersSymbolVisually = true
            view.showsShadow = false
            view.cornerRadius = 12
            view.hoverBackgroundColor = Palette.border.withAlphaComponent(0.5)
            view.setAccessibilityLabel(OnboardingStrings.videoCallsShowExample(app: guide.name))
            view.onClick = { [weak self] in self?.selectPage(index) }
            return view
        }
    }()

    /// Wraps from WeChat back to the first example.
    private lazy var nextPage: Button = {
        let view = Button(style: .plain)
        view.symbolName = "chevron.right"
        view.iconSize = 12
        view.centersSymbolVisually = true
        view.showsShadow = false
        view.cornerRadius = 14
        view.hoverBackgroundColor = Palette.border.withAlphaComponent(0.5)
        view.setAccessibilityLabel(OnboardingStrings.nextGuideImage)
        view.onClick = { [weak self] in
            guard let self else { return }
            self.selectPage(((self.selectedPage ?? 0) + 1) % self.guides.count)
        }
        return view
    }()

    /// Composes static screenshots without inspecting or controlling third-party applications.
    init() {
        super.init()
        for image in images { addSubview(image) }
        [appName, caption, pagination].forEach(addSubview)
        for button in [previousPage] + pageDots + [nextPage] { pagination.addArrangedSubview(button) }
        [previousPage, nextPage].forEach { button in
            button.snp.makeConstraints { make in make.size.equalTo(28) }
        }
        pageDots.forEach { button in
            button.snp.makeConstraints { make in make.size.equalTo(24) }
        }
        pagination.snp.makeConstraints { make in
            make.centerX.bottom.equalToSuperview()
            make.height.equalTo(28)
        }
        caption.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(pagination.snp.top).offset(-10)
            make.height.greaterThanOrEqualTo(34)
        }
        appName.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(caption.snp.top).offset(-6)
            make.height.equalTo(20)
        }
        for image in images {
            image.snp.makeConstraints { make in
                make.leading.trailing.top.equalToSuperview()
                make.bottom.equalTo(appName.snp.top).offset(-12)
            }
        }
        selectPage(0)
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Recomputes caption height for the current guide-column width while keeping originals proportional.
    override func layout() {
        if bounds.width > 0, caption.preferredMaxLayoutWidth != bounds.width {
            caption.preferredMaxLayoutWidth = bounds.width
        }
        super.layout()
    }

    /// Changes the example, app name, explanation, and selected dot as one manual page selection.
    private func selectPage(
        _ page: Int
    ) {
        guard guides.indices.contains(page), selectedPage != page else { return }
        selectedPage = page
        let guide = guides[page]
        appName.stringValue = guide.name
        caption.stringValue = guide.caption
        for (index, image) in images.enumerated() {
            ControlMotion.setOpacity(
                index == page ? 1 : 0,
                on: image
            )
            image.setAccessibilityElement(index == page)
        }
        for (index, dot) in pageDots.enumerated() {
            dot.foregroundColor = index == page ? Palette.accent : Palette.border
            dot.setAccessibilityValue(NSNumber(value: index == page))
        }
        if window != nil {
            NSAccessibility.post(
                element: appName,
                notification: .valueChanged
            )
        }
    }
}
