//
//  GenerationThumbnailView.swift
//  FaceNow
//

import AppKit
import Kingfisher
import SnapKit

/// Crops cached thumbnails to fill their circle without stretching the source image.
final class GenerationThumbnailView: NSImageView {

    /// The image identity used to avoid restarting an unchanged thumbnail request.
    private var sourceID: String?

    /// Gives prompt-only presets a readable title without making an image request.
    private lazy var promptLabel: NSTextField = {
        let view = NSTextField(wrappingLabelWithString: "")
        view.font = .systemFont(ofSize: 10)
        view.textColor = Palette.secondary
        view.alignment = .center
        view.maximumNumberOfLines = 3
        view.lineBreakMode = .byWordWrapping
        view.cell?.truncatesLastVisibleLine = true
        view.isHidden = true
        return view
    }()

    /// Whether layout coordinates start at the top-left corner.
    override var isFlipped: Bool { true }

    /// Lets pointer events reach the native reference control beneath decorative content.
    override func hitTest(
        _ point: NSPoint
    ) -> NSView? { nil }

    /// Creates a clipped thumbnail view without starting an image request.
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityElement(false)
        addSubview(promptLabel)
        promptLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(8)
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview().inset(8)
            make.bottom.lessThanOrEqualToSuperview().inset(8)
        }
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Applies the current reference, selection, or availability without unnecessary image reloads.
    func configure(
        _ reference: GenerationReference?
    ) {
        guard sourceID != reference?.id else { return }
        kf.cancelDownloadTask()
        sourceID = reference?.id
        image = nil
        promptLabel.isHidden = reference == nil || reference?.thumbnailURL != nil || reference?.thumbnailData != nil
        promptLabel.stringValue = reference?.name ?? ""
        guard let reference else { return }
        let source: Source
        var options: KingfisherOptionsInfo = [
            .backgroundDecode, .scaleFactor(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2),
        ]
        if let data = reference.thumbnailData {
            source = .provider(
                RawImageDataProvider(
                    data: data,
                    cacheKey: reference.id
                )
            )
            options += [
                .cacheMemoryOnly,
                .processor(
                    DownsamplingImageProcessor(
                        size: CGSize(
                            width: 80,
                            height: 80
                        )
                    )
                ),
            ]
        } else if let url = reference.thumbnailURL, url.isFileURL {
            source = .provider(LocalFileImageDataProvider(fileURL: url))
            options.append(
                .processor(
                    DownsamplingImageProcessor(
                        size: CGSize(
                            width: 80,
                            height: 80
                        )
                    )
                )
            )
        } else if let url = reference.thumbnailURL {
            source = .network(KF.ImageResource(downloadURL: url))
        } else {
            return
        }
        // Remote URLs already request COS thumbnails; downloading the full image is unnecessary.
        kf.setImage(
            with: source,
            options: options
        )
    }

    /// Cancels pending thumbnail work while preserving an image already decoded.
    func cancel() {
        kf.cancelDownloadTask()
        if image == nil { sourceID = nil }
    }

    /// Places the current reference content within the host-provided bounds.
    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    /// Draws the reference's cropped image or its upload and selection decoration.
    override func draw(
        _ dirtyRect: NSRect
    ) {
        Palette.surface.setFill()
        bounds.fill()
        guard let image, image.size.width > 0, image.size.height > 0 else {
            guard promptLabel.isHidden else { return }
            let symbol = NSImage(
                systemSymbolName: "photo",
                accessibilityDescription: nil
            )
            symbol?.draw(
                in: NSRect(
                    x: bounds.midX - 8,
                    y: bounds.midY - 8,
                    width: 16,
                    height: 16
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 0.3,
                respectFlipped: true,
                hints: nil
            )
            return
        }
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let crop = NSRect(
            x: (image.size.width - bounds.width / scale) / 2,
            y: (image.size.height - bounds.height / scale) / 2,
            width: bounds.width / scale,
            height: bounds.height / scale
        )
        image.draw(
            in: bounds,
            from: crop,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }
}
