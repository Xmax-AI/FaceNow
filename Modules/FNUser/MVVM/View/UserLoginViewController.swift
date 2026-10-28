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

    /// The content group keeps the heading and form centered as one unit.
    private lazy var formContent: Canvas = {
        let view = Canvas()
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
        imageView.image = NSImage(named: NSImage.applicationIconName)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityLabel("FaceNow")
        return imageView
    }()

    /// The account form heading.
    private lazy var heading: NSTextField = {
        let view = makeLabel(
            "Welcome to FaceNow",
            size: 36,
            weight: .semibold
        )
        view.alignment = .center
        return view
    }()

    /// Explains the benefit of signing in without exposing implementation details.
    private lazy var subtitle: NSTextField = {
        let view = makeLabel(
            "A new look for every camera moment",
            size: 16,
            color: Palette.secondary
        )
        view.alignment = .center
        return view
    }()

    /// The short caption over the product demonstration.
    private lazy var caption: NSTextField = {
        let view = makeLabel(
            "Be different.\nBe you.",
            size: 38,
            color: .white,
            weight: .semibold
        )
        view.maximumNumberOfLines = 2
        view.lineBreakMode = .byWordWrapping
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
        [appIcon, heading, subtitle, formView].forEach(formContent.addSubview)
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
        showcase.addSubview(caption)
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
    }

    /// Stops decorative playback when the account page leaves the screen.
    override func viewWillDisappear() {
        super.viewWillDisappear()
        player.pause()
    }

    /// Cancels pending form requests and stops decorative media on dismissal or app shutdown.
    func shutdown() {
        (formView as? UserLoginFormView)?.shutdown()
        player.pause()
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
            make.width.lessThanOrEqualTo(480)
            make.width.greaterThanOrEqualTo(240)
            make.height.equalTo(max(200, formView.fittingSize.height) + 234)
            make.top.greaterThanOrEqualToSuperview().offset(30)
            make.centerY.equalToSuperview().offset(5).priority(750)
        }
        appIcon.snp.makeConstraints { make in
            make.centerX.top.equalToSuperview()
            make.size.equalTo(72)
        }
        heading.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(appIcon.snp.bottom).offset(28)
            make.height.equalTo(48)
        }
        subtitle.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(heading.snp.bottom).offset(12)
            make.height.equalTo(26)
        }
        formView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalToSuperview().offset(234)
        }
        caption.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(32)
            make.bottom.equalToSuperview().inset(32)
            make.height.equalTo(104)
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
