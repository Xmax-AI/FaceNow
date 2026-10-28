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
import SnapKit
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
        view.font = .systemFont(ofSize: 14)
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
        view.font = .systemFont(ofSize: 12)
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
        view.font = .systemFont(ofSize: 13, weight: .semibold)
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
        configureLayout()
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

    /// Keeps preview bindings and overlays attached using native view constraints.
    private func configureLayout() {
        videoContainer.snp.makeConstraints { make in make.edges.equalToSuperview() }
        video.snp.makeConstraints { make in make.edges.equalToSuperview() }
        placeholder.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(20)
            make.centerY.equalToSuperview()
            make.height.equalTo(20)
        }
        captionBackground.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.bottom.equalToSuperview().inset(12)
        }
        caption.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(6)
            make.top.bottom.equalToSuperview().inset(3)
        }
        watermark.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.trailing.equalToSuperview().inset(16)
        }
        var previous: GenerationStatisticsPanel?
        for panel in panels {
            panel.snp.makeConstraints { make in
                make.leading.equalToSuperview().offset(14)
                make.width.equalTo(panel.panelWidth)
                make.height.equalTo(panel.panelHeight)
                if let previous {
                    make.top.equalTo(previous.snp.bottom).offset(8)
                } else {
                    make.top.equalToSuperview().offset(12)
                }
            }
            previous = panel
        }
    }
}
