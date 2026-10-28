//
//  GenerationVideoPanel.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import XmaxSDK

/// The SDK view remains attached throughout startup and page transitions.
final class GenerationVideoPanel: Canvas {

    /// The SDK preview view whose binding remains attached during page transitions.
    private lazy var video: XmaxRealtimeVideoView = {
        let view = XmaxRealtimeVideoView()
        // Mirror presentation only; capture, uplink and virtual-camera frames keep their original direction.
        view.isMirrored = true
        return view
    }()

    /// The video canvas retaining the SDK view at the panel dimensions.
    private lazy var videoContainer: Canvas = {
        let view = Canvas(color: .black)
        return view
    }()

    /// The connection or generation hint displayed over unavailable output.
    private lazy var placeholder: NSTextField = {
        let view = makeLabel(
            size: 14,
            color: .white.withAlphaComponent(0.55)
        )
        view.alignment = .center
        return view
    }()

    /// The immutable Local or Result caption supplied by the workspace.
    private let title: String

    /// Whether this panel presents the result-only product watermark.
    private let showsWatermark: Bool

    /// The lazily created native panel-title label.
    private lazy var caption: NSTextField = {
        let view = makeLabel(
            title,
            size: 12,
            color: .white.withAlphaComponent(0.65)
        )
        return view
    }()

    /// The translucent background keeping the panel caption readable.
    private lazy var captionBackground: Canvas = {
        let view = Canvas(
            color: .black.withAlphaComponent(0.35),
            radius: 8
        )
        return view
    }()

    /// The FaceNow watermark shown only on the result panel.
    private lazy var watermark: NSTextField = {
        let view = makeLabel(
            "✦ FaceNow",
            size: 13,
            color: .white.withAlphaComponent(0.8),
            weight: .semibold
        )
        view.isHidden = !showsWatermark
        return view
    }()

    /// The persistent overlays for the panel's metric groups.
    private var panels: [GenerationStatisticsPanel] = []

    /// Creates the persistent SDK preview and its caption, watermark, and statistics overlays.
    init(
        title: String,
        statistics: [GenerationStatisticsGroup],
        showsWatermark: Bool = false
    ) {
        self.title = title
        self.showsWatermark = showsWatermark
        super.init(
            color: .black,
            radius: 24
        )
        layer?.masksToBounds = true
        addSubview(videoContainer)
        videoContainer.addSubview(video)
        addSubview(placeholder)
        for group in statistics {
            let panel = GenerationStatisticsPanel(group: group)
            panels.append(panel)
            addSubview(panel)
        }
        addSubview(captionBackground)
        captionBackground.addSubview(caption)
        addSubview(watermark)
        setAccessibilityLabel(title)
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Binds the current track and updates presentation without replacing the SDK view.
    func update(
        track: RealtimeVideoTrack?,
        message: String,
        statistics: [GenerationStatisticsGroup],
        visible: Bool
    ) {
        video.track = track
        if placeholder.stringValue != message { placeholder.stringValue = message }
        placeholder.isHidden = message.isEmpty
        for (panel, group) in zip(
            panels,
            statistics
        ) {
            panel.isHidden = !visible
            panel.update(group)
        }
    }

    /// Places the video, caption, watermark, and measured statistics overlays.
    override func layout() {
        super.layout()
        videoContainer.frame = bounds
        video.frame = videoContainer.bounds
        placeholder.frame = NSRect(
            x: 20,
            y: bounds.midY - 10,
            width: bounds.width - 40,
            height: 20
        )
        let captionSize = Typography.size(
            caption.stringValue,
            font: caption.font!
        )
        captionBackground.frame = NSRect(
            x: 14,
            y: bounds.height - 12 - captionSize.height - 6,
            width: ceil(captionSize.width) + 16,
            height: captionSize.height + 6
        )
        caption.frame = NSRect(
            x: 6,
            y: 3,
            width: ceil(captionSize.width) + 4,
            height: captionSize.height
        )
        let watermarkSize = Typography.size(
            watermark.stringValue,
            font: watermark.font!
        )
        watermark.frame = NSRect(
            x: bounds.width - 16 - watermarkSize.width - 2,
            y: 12,
            width: watermarkSize.width + 4,
            height: watermarkSize.height
        )
        var y: CGFloat = 12
        for panel in panels {
            panel.frame = NSRect(
                x: 14,
                y: y,
                width: panel.panelWidth,
                height: panel.panelHeight
            )
            y += panel.panelHeight + 8
        }
    }
}
