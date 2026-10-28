//
//  HomeFooterView.swift
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
import Kingfisher

/// Owns product links and the WeChat follow popover on the home page.
@MainActor
final class HomeFooterView: Canvas {

    /// The shared visible spacing between the version and adjacent footer destinations.
    private static let itemSpacing: CGFloat = 40

    /// The module-owned destinations shared with home navigation.
    @Injected(\.homeRepo) private var homeRepo: HomeRepository

    /// Opens the product's WeChat follow information.
    private lazy var wechat: Button = {
        let view = Button(
            icon: .wechat,
            style: .plain
        )
        view.foregroundColor = Palette.secondary.withAlphaComponent(0.75)
        view.iconSize = 20
        view.setAccessibilityLabel("WeChat")
        view.onClick = { [weak self] in self?.showWeChat() }
        return view
    }()

    /// Opens the product's X profile after an explicit click.
    private lazy var social: Button = {
        let view = Button(
            icon: .socialX,
            style: .plain
        )
        view.foregroundColor = Palette.secondary.withAlphaComponent(0.75)
        view.iconSize = 18
        view.setAccessibilityLabel("X")
        view.onClick = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.homeRepo.socialURL)
        }
        return view
    }()

    /// Opens the product website after an explicit click.
    private lazy var website: Button = {
        let view = Button(
            icon: .globe,
            style: .plain
        )
        view.foregroundColor = Palette.secondary.withAlphaComponent(0.75)
        view.iconSize = 20
        view.setAccessibilityLabel(HomeStrings.homeWebsite)
        view.onClick = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.homeRepo.websiteURL)
        }
        return view
    }()

    /// Opens the product contact destination after an explicit click.
    private lazy var contact: Button = {
        let view = Button(
            HomeStrings.homeFeedback,
            style: .plain
        )
        view.onClick = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.homeRepo.contactURL)
        }
        return view
    }()

    /// Opens the Xmax API platform after an explicit click.
    private lazy var platform: Button = {
        let view = Button(
            HomeStrings.homeAPIPlatform,
            style: .plain
        )
        view.onClick = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.homeRepo.platformURL)
        }
        return view
    }()

    /// Reserves the documentation entry until its destination URL is supplied.
    private lazy var troubleshooting: Button = {
        let view = Button(
            HomeStrings.troubleshooting,
            style: .plain
        )
        return view
    }()

    /// The public version label before the footer links, using the native system font.
    private lazy var version: NSTextField = {
        let view = makeLabel(
            HomeStrings.version(homeRepo.appVersion),
            color: Palette.secondary
        )
        view.font = .systemFont(
            ofSize: contact.font?.pointSize ?? 13,
            weight: .regular
        )
        view.alignment = .right
        return view
    }()

    /// Retains only the footer's transient popover.
    private var popover: NSPopover?

    /// Creates the footer links without opening external destinations.
    init() {
        super.init()
        [wechat, social, website, contact, platform, troubleshooting, version].forEach(addSubview)
        configureLayout()
    }

    /// Storyboard decoding is unsupported for this programmatic view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Places social links and platform destinations on their original footer row.
    private func configureLayout() {
        for (index, button) in [wechat, social, website].enumerated() {
            button.snp.makeConstraints { make in
                make.leading.equalToSuperview().offset(CGFloat(index) * 52)
                make.top.equalToSuperview().offset(56)
                make.size.equalTo(24)
            }
        }
        platform.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.top.equalToSuperview().offset(56)
            make.width.equalTo(platform.preferredWidth)
            make.height.equalTo(26)
        }
        contact.snp.makeConstraints { make in
            make.trailing.equalTo(platform.snp.leading).offset(-Self.itemSpacing)
            make.top.height.equalTo(platform)
            make.width.equalTo(contact.preferredWidth)
        }
        troubleshooting.snp.makeConstraints { make in
            make.trailing.equalTo(contact.snp.leading).offset(-Self.itemSpacing)
            make.top.height.equalTo(contact)
            make.width.equalTo(troubleshooting.preferredWidth)
        }
        version.snp.makeConstraints { make in
            make.trailing.equalTo(troubleshooting.snp.leading).offset(-Self.itemSpacing)
            make.centerY.equalTo(contact)
        }
    }

    /// Dismisses the footer popover during transitions and shutdown.
    func closePopover() {
        popover?.close()
        popover = nil
    }

    /// Popovers use native fields and controls, keeping keyboard editing independent of session redraws.
    private func presentPopover(
        content: NSView,
        from button: NSView
    ) {
        popover?.close()
        let controller = NSViewController()
        controller.view = content
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.contentSize = content.fittingSize
        self.popover = popover
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .maxY
        )
    }

    /// Presents the follow QR image and caption inside the footer-owned popover.
    private func showWeChat() {
        let content = Canvas()

        content.snp.makeConstraints { make in
            make.width.equalTo(208)
            make.height.equalTo(242)
        }
        let image = NSImageView()
        image.imageScaling = .scaleProportionallyUpOrDown
        image.kf.setImage(
            with: homeRepo.wechatImageURL,
            options: [
                .processor(
                    DownsamplingImageProcessor(
                        size: NSSize(
                            width: 180,
                            height: 180
                        )
                    )
                ),
                .scaleFactor(window?.backingScaleFactor ?? 2), .backgroundDecode,
            ]
        )
        let label = makeLabel(
            HomeStrings.homeScanWithWeChatToFollowUs,
            size: 12
        )
        label.alignment = .center

        content.addSubview(image)
        content.addSubview(label)
        image.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(14)
            make.height.equalTo(image.snp.width)
        }
        label.snp.makeConstraints { make in
            make.leading.trailing.equalTo(image)
            make.top.equalTo(image.snp.bottom).offset(8)
            make.height.equalTo(24)
        }
        presentPopover(
            content: content,
            from: wechat
        )
    }

}
