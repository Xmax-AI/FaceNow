//
//  UserLoginScenariosView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import SnapKit

/// Presents bundled monochrome communication-app silhouettes on a seamless rightward loop.
@MainActor
final class UserLoginScenariosView: Canvas {

    /// The artwork order repeated by each identical strip.
    private static let icons: [(name: String, asset: String)] = [
        ("WeChat", "ScenarioWeChat"),
        ("Zoom", "ScenarioZoom"),
        ("Tencent Meeting", "ScenarioTencentMeeting"),
        ("Feishu", "ScenarioFeishu"),
        ("Microsoft Teams", "ScenarioTeams"),
        ("Google Meet", "ScenarioGoogleMeet"),
        ("DingTalk", "ScenarioDingTalk"),
        ("QQ", "ScenarioQQ"),
        ("Discord", "ScenarioDiscord"),
        ("Slack", "ScenarioSlack"),
        ("Telegram", "ScenarioTelegram"),
        ("WhatsApp", "ScenarioWhatsApp"),
    ]

    /// The same subdued tint and opacity shared by the heading and brand silhouettes.
    private static let contentColor = Palette.secondary.withAlphaComponent(0.4)

    /// The fixed slot width keeps the loop's seam independent of viewport resizing.
    private let slotWidth: CGFloat = 68

    /// Whether the owning login page is currently visible.
    private var isPlaying = false

    /// The centered section label uses the application's shared typography.
    private lazy var title: NSTextField = {
        let view = makeLabel(
            UserStrings.scenarios,
            size: 16,
            color: Self.contentColor,
            weight: .medium
        )
        view.alignment = .center
        return view
    }()

    /// Clips the repeated strips at the account column's edges.
    private lazy var viewport: Canvas = {
        let view = Canvas()
        view.layer?.masksToBounds = true
        view.layer?.mask = edgeFade
        return view
    }()

    /// Softens the entrance and exit of the moving artwork.
    private let edgeFade: CAGradientLayer = {
        let value = CAGradientLayer()
        value.colors = [
            NSColor.clear.cgColor, NSColor.black.cgColor,
            NSColor.black.cgColor, NSColor.clear.cgColor,
        ]
        value.locations = [0, 0.08, 0.92, 1]
        value.startPoint = CGPoint(x: 0, y: 0.5)
        value.endPoint = CGPoint(x: 1, y: 0.5)
        return value
    }()

    /// Holds three identical strips so a full-period translation never reveals a gap.
    private let track = CALayer()

    /// Draws the two dashed lines around the section label.
    private let divider: CAShapeLayer = {
        let value = CAShapeLayer()
        value.strokeColor = Palette.secondary.withAlphaComponent(0.28).cgColor
        value.fillColor = nil
        value.lineWidth = 1
        value.lineDashPattern = [3, 4]
        return value
    }()

    /// Creates the offline artwork once without performing network requests.
    init() {
        super.init()
        layer?.addSublayer(divider)
        [title, viewport].forEach(addSubview)
        title.snp.makeConstraints { make in
            make.centerX.top.equalToSuperview()
            make.height.equalTo(24)
        }
        viewport.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalToSuperview().offset(34)
            make.height.equalTo(52)
        }
        viewport.layer?.addSublayer(track)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(UserStrings.scenarios + ": " + Self.icons.map(\.name).joined(separator: ", "))
        let silhouettes = Self.icons.map { icon in
            NSImage(named: icon.asset)?.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            )
        }
        for copy in 0..<3 {
            for index in Self.icons.indices {
                let artwork = CALayer()
                artwork.backgroundColor = Self.contentColor.cgColor
                artwork.frame = CGRect(
                    x: CGFloat(copy * Self.icons.count + index) * slotWidth + 18,
                    y: 10,
                    width: 32,
                    height: 32
                )
                let mask = CALayer()
                mask.contents = silhouettes[index]
                mask.contentsGravity = .resizeAspect
                mask.frame = artwork.bounds
                artwork.mask = mask
                track.addSublayer(artwork)
            }
        }
    }

    /// Storyboard decoding is unsupported for this programmatic view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Starts decorative motion only while the owning page is visible.
    func start() {
        isPlaying = true
        updateAnimation()
    }

    /// Releases the animation when the login page disappears or shuts down.
    func stop() {
        isPlaying = false
        track.removeAnimation(forKey: "scenarioScroll")
    }

    /// Aligns the heading, dashed rules, and fixed-size icon track when the window resizes.
    override func layout() {
        super.layout()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 12))
        path.addLine(to: CGPoint(x: max(0, title.frame.minX - 18), y: 12))
        path.move(to: CGPoint(x: min(bounds.width, title.frame.maxX + 18), y: 12))
        path.addLine(to: CGPoint(x: bounds.width, y: 12))
        let period = CGFloat(Self.icons.count) * slotWidth
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        divider.frame = bounds
        divider.path = path
        edgeFade.frame = viewport.bounds
        track.frame = CGRect(
            x: -period,
            y: 0,
            width: period * 3,
            height: viewport.bounds.height
        )
        CATransaction.commit()
        updateAnimation()
    }

    /// Uses one exact strip width per linear cycle and respects reduced-motion preferences.
    private func updateAnimation() {
        guard isPlaying, window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            track.removeAnimation(forKey: "scenarioScroll")
            return
        }
        guard track.animation(forKey: "scenarioScroll") == nil else { return }
        let period = CGFloat(Self.icons.count) * slotWidth
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = period
        animation.duration = Double(period) / 22
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        track.add(
            animation,
            forKey: "scenarioScroll"
        )
    }
}
