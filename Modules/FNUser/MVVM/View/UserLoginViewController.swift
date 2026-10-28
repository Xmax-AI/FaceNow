//
//  UserLoginViewController.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import AVFoundation
import SnapKit

/// Presents the account form beside the product's muted demonstration video.
///
/// The supplied form owns its authentication actions. This page only manages
/// presentation and stops its video when detached or dismissed.
@MainActor
final class UserLoginViewController: NSViewController {

    /// The authentication form supplied by the account flow.
    private let formView: NSView

    /// The bounded viewport scale currently applied to the account column.
    private var layoutScale: CGFloat = 1

    /// The page canvas using the application's existing light appearance.
    private lazy var canvas: Canvas = {
        let view = Canvas(color: .white)
        return view
    }()

    /// The rounded demonstration panel containing the local video.
    private lazy var showcase: Canvas = {
        let view = Canvas(
            color: .black,
            radius: 24
        )
        view.layer?.masksToBounds = true
        return view
    }()

    /// The right column centers the account controls beside the demonstration.
    private lazy var formColumn: Canvas = {
        let view = Canvas()
        return view
    }()

    /// The shared horizontal alignment for the header, input region, and scenarios footer.
    private lazy var formContent: Canvas = {
        let view = Canvas()
        return view
    }()

    /// The independent top section containing the application identity and welcome text.
    private lazy var headerContent: Canvas = {
        let view = Canvas()
        return view
    }()

    /// Centers authentication within the space between the header and footer.
    private lazy var inputContent: Canvas = {
        let view = Canvas()
        return view
    }()

    /// The offline communication-app showcase below the account form.
    private lazy var scenarios: UserLoginScenariosView = {
        let view = UserLoginScenariosView()
        return view
    }()

    /// The native player layer, kept separate from AppKit text and controls.
    private let playerLayer: AVPlayerLayer = {
        let value = AVPlayerLayer()
        value.videoGravity = .resizeAspectFill
        return value
    }()

    /// Shows the first demonstration frame during loading and reduced-motion playback.
    private let posterLayer = CALayer()

    /// Loops the small local demonstration without audio or network traffic.
    private let player: AVQueuePlayer = {
        let value = AVQueuePlayer()
        value.isMuted = true
        return value
    }()

    /// Retains the loop and its template item while the page is alive.
    private var looper: AVPlayerLooper?

    /// Darkens the lower video edge so the product caption stays legible.
    private let shade: CAGradientLayer = {
        let value = CAGradientLayer()
        value.colors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.78).cgColor]
        value.startPoint = CGPoint(
            x: 0.5,
            y: 0
        )
        value.endPoint = CGPoint(
            x: 0.5,
            y: 1
        )
        return value
    }()

    /// The application icon centered above the welcome heading.
    private lazy var appIcon: NSImageView = {
        let imageView = NSImageView()
        imageView.image = NSApplication.shared.applicationIconImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityLabel("FaceNow")
        return imageView
    }()

    /// The account form heading.
    private lazy var heading: NSTextField = {
        let view = makeLabel(
            UserStrings.welcome,
            size: 34,
            weight: .semibold
        )
        view.alignment = .center
        return view
    }()

    /// Explains the benefit of signing in without exposing implementation details.
    private lazy var subtitle: NSTextField = {
        let view = makeLabel(
            UserStrings.subtitle,
            size: 17,
            color: Palette.secondary
        )
        view.alignment = .center
        return view
    }()

    /// The single-line product slogan over the demonstration.
    private lazy var caption: NSTextField = {
        let view = makeLabel(
            UserStrings.slogan,
            size: 38,
            color: .white,
            weight: .semibold
        )
        view.maximumNumberOfLines = 1
        view.lineBreakMode = .byClipping
        return view
    }()

    /// Credits the model powering the product beneath the slogan.
    private lazy var captionDetail: NSTextField = {
        let view = makeLabel(
            UserStrings.modelCredit,
            size: 12.5,
            color: .white.withAlphaComponent(0.8)
        )
        view.maximumNumberOfLines = 1
        view.lineBreakMode = .byClipping
        return view
    }()

    /// Creates the page around the supplied native account form.
    init(
        formView: NSView
    ) {
        self.formView = formView
        super.init(
            nibName: nil,
            bundle: nil
        )
    }

    /// Storyboard decoding is unsupported for this programmatic page.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Installs native content and the bundled demonstration with muted playback.
    override func loadView() {
        view = canvas
        [showcase, formColumn].forEach(canvas.addSubview)
        formColumn.addSubview(formContent)
        [headerContent, inputContent, scenarios].forEach(formContent.addSubview)
        [appIcon, heading, subtitle].forEach(headerContent.addSubview)
        inputContent.addSubview(formView)
        showcase.layer?.addSublayer(posterLayer)
        if let url = Bundle.main.url(
            forResource: "FaceNowLoginPoster",
            withExtension: "png"
        ),
            let image = NSImage(contentsOf: url)
        {
            posterLayer.contents = image
            posterLayer.contentsGravity = .resizeAspectFill
        }
        showcase.layer?.addSublayer(playerLayer)
        showcase.layer?.addSublayer(shade)
        [caption, captionDetail].forEach(showcase.addSubview)
        configureLayout()
        playerLayer.player = player
        if let url = Bundle.main.url(
            forResource: "FaceNowLogin",
            withExtension: "mp4"
        ) {
            looper = AVPlayerLooper(
                player: player,
                templateItem: AVPlayerItem(url: url)
            )
        }
    }

    /// Starts playback only while the page is visible and motion is allowed.
    override func viewDidAppear() {
        super.viewDidAppear()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { player.play() }
        scenarios.start()
    }

    /// Stops decorative playback when the account page leaves the screen.
    override func viewWillDisappear() {
        super.viewWillDisappear()
        player.pause()
        scenarios.stop()
    }

    /// Cancels pending form requests and stops decorative media on dismissal or app shutdown.
    func shutdown() {
        (formView as? UserLoginFormView)?.shutdown()
        player.pause()
        scenarios.stop()
    }

    /// Constrains the page's two columns and keeps the form width readable while resizing.
    private func configureLayout() {
        showcase.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().offset(20)
            make.bottom.equalToSuperview().inset(20)
            make.width.equalTo(canvas.snp.width).multipliedBy(0.5).offset(-20).priority(999)
            make.width.greaterThanOrEqualTo(280)
        }
        formColumn.snp.makeConstraints { make in
            make.leading.equalTo(showcase.snp.trailing)
            make.top.trailing.bottom.equalToSuperview()
        }
        formContent.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(48)
            make.trailing.lessThanOrEqualToSuperview().inset(48)
            // Let the form stop growing at its width cap without limiting native window resizing.
            make.width.equalTo(formColumn.snp.width).multipliedBy(0.82).priority(490)
            make.width.lessThanOrEqualTo(560)
            make.width.greaterThanOrEqualTo(240)
            make.top.bottom.equalToSuperview()
        }
        headerContent.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalToSuperview().offset(80)
            make.bottom.equalTo(subtitle.snp.bottom)
        }
        inputContent.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(subtitle.snp.bottom).offset(24)
            make.bottom.equalTo(scenarios.snp.top).offset(-24)
        }
        scenarios.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalToSuperview().inset(24)
            make.height.equalTo(88)
        }
        appIcon.snp.makeConstraints { make in
            make.centerX.top.equalToSuperview()
            make.size.equalTo(112)
        }
        heading.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(appIcon.snp.bottom).offset(20)
            make.height.equalTo(48)
        }
        subtitle.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(heading.snp.bottom).offset(8)
            make.height.equalTo(26)
        }
        formView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.centerY.equalToSuperview().priority(750)
            // Allow the viewport to resize before the next pass applies its responsive scale.
            make.top.greaterThanOrEqualToSuperview().priority(490)
            make.bottom.lessThanOrEqualToSuperview().priority(490)
        }
        caption.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(32)
            make.bottom.equalTo(captionDetail.snp.top).offset(-12)
            make.height.equalTo(50)
        }
        captionDetail.snp.makeConstraints { make in
            make.leading.equalTo(caption).offset(2)
            make.trailing.equalTo(caption)
            make.bottom.equalToSuperview().inset(32)
            make.height.equalTo(18)
        }
    }

    /// Updates existing account-column metrics before Auto Layout places its persistent controls.
    override func viewWillLayout() {
        super.viewWillLayout()
        let availableScale = min(canvas.bounds.width / 1440, canvas.bounds.height / 900)
        let scale = (min(1.1, max(0.9, availableScale)) * 100).rounded() / 100
        guard abs(layoutScale - scale) > 0.001 else { return }
        layoutScale = scale
        (formView as? UserLoginFormView)?.applyLayoutScale(scale)
        heading.font = Typography.font(
            size: 34 * scale,
            weight: .semibold
        )
        subtitle.font = Typography.font(size: 17 * scale)
        formContent.snp.updateConstraints { make in
            make.width.lessThanOrEqualTo(560 * scale)
        }
        headerContent.snp.updateConstraints { make in
            make.top.equalToSuperview().offset(80 * scale)
        }
        inputContent.snp.updateConstraints { make in
            make.top.equalTo(subtitle.snp.bottom).offset(24 * scale)
            make.bottom.equalTo(scenarios.snp.top).offset(-24 * scale)
        }
        appIcon.snp.updateConstraints { make in make.size.equalTo(112 * scale) }
        heading.snp.updateConstraints { make in
            make.top.equalTo(appIcon.snp.bottom).offset(20 * scale)
            make.height.equalTo(48 * scale)
        }
        subtitle.snp.updateConstraints { make in
            make.top.equalTo(heading.snp.bottom).offset(8 * scale)
            make.height.equalTo(26 * scale)
        }
    }

    /// Resizes Core Animation's media layers after Auto Layout has placed their host view.
    override func viewDidLayout() {
        super.viewDidLayout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = showcase.bounds
        posterLayer.frame = showcase.bounds
        shade.frame = showcase.bounds
        CATransaction.commit()
    }
}
