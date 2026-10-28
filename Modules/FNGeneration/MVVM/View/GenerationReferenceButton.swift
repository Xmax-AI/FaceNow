//
//  GenerationReferenceButton.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import SnapKit

/// Reusable native reference buttons update selection and upload progress in place.
final class GenerationReferenceButton: NSButton {

    /// The retained thumbnail view used by this reference button.
    lazy var thumbnail: GenerationThumbnailView = {
        let view = GenerationThumbnailView()
        return view
    }()

    /// The upload progress animation displayed over the thumbnail.
    private lazy var spinner: Spinner = {
        let view = Spinner()
        view.isHidden = true
        return view
    }()

    /// The reference whose identity and upload progress are currently rendered.
    private var reference: GenerationReference?

    /// Whether this reference represents the current generation selection.
    private var selected = false

    /// The title color follows the same transition duration as the thumbnail outline.
    @objc dynamic private var selectionProgress: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    /// Supplies native interpolation for the custom-drawn selection color.
    override class func defaultAnimation(
        forKey key: NSAnimatablePropertyKey
    ) -> Any? {
        if key == "selectionProgress" { return CABasicAnimation() }
        return super.defaultAnimation(forKey: key)
    }

    /// Whether an initial reference state has already been applied.
    private var configured = false

    /// Whether the pointer is currently inside the control.
    private var hovered = false

    /// The current visible-bounds tracking area.
    private var hoverArea: NSTrackingArea?

    /// The action invoked when the user activates this control.
    var onClick: (() -> Void)?

    /// Whether the reference uses the smaller Free Prompt presentation.
    var compact = false

    /// Whether layout coordinates start at the top-left corner.
    override var isFlipped: Bool { true }

    /// Creates a persistent reference control with retained image and progress views.
    init() {
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(invoke)
        addSubview(thumbnail)
        addSubview(overlay)
        overlay.addSubview(progressLabel)
        addSubview(spinner)
        thumbnail.snp.makeConstraints { make in
            make.centerX.top.equalToSuperview()
            make.size.equalTo(64)
        }
        spinner.snp.makeConstraints { make in
            make.centerX.equalTo(thumbnail)
            make.centerY.equalTo(thumbnail).offset(-6)
            make.size.equalTo(16)
        }
        overlay.snp.makeConstraints { make in make.edges.equalTo(thumbnail) }
        progressLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.centerY.equalToSuperview().offset(13)
            make.height.equalTo(14)
        }
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Invokes the enabled control action without replacing its native identity.
    @objc private func invoke() { onClick?() }

    /// Applies the current reference, selection, or availability without unnecessary image reloads.
    func configure(
        _ reference: GenerationReference?,
        selected: Bool,
        enabled: Bool
    ) {
        thumbnail.configure(reference)
        let canSelect = enabled && reference?.uploadState != .uploading
        guard
            !configured || self.reference?.id != reference?.id || self.selected != selected
                || self.reference?.uploadState != reference?.uploadState
                || self.reference?.uploadProgress != reference?.uploadProgress
                || self.reference?.uploadError != reference?.uploadError || isEnabled != canSelect
        else { return }
        configured = true
        self.reference = reference
        let selectionChanged = self.selected != selected
        self.selected = selected
        if selectionChanged {
            ControlMotion.animate(in: self) {
                animator().selectionProgress = selected ? 1 : 0
            }
        }
        isEnabled = canSelect
        thumbnail.isHidden = reference == nil
        spinner.setSpinning(
            reference?.uploadState == .uploading,
            color: .white
        )
        toolTip =
            reference?.uploadError.map { $0 + " — Click to retry" } ?? reference?.name
            ?? "Upload your own reference image"
        setAccessibilityLabel(reference?.name ?? "Upload reference image")
        setAccessibilityValue(selected ? "Selected" : "")
        needsDisplay = true
        needsLayout = true
    }

    /// Replaces the hover-tracking area for the current visible bounds.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        hoverArea = area
    }

    /// Marks the control as hovered and requests an appearance update.
    override func mouseEntered(
        with event: NSEvent
    ) {
        hovered = true
        needsDisplay = true
    }

    /// Clears hover presentation when the pointer leaves the control.
    override func mouseExited(
        with event: NSEvent
    ) {
        hovered = false
        needsDisplay = true
    }

    /// Places the current reference content within the host-provided bounds.
    override func layout() {
        super.layout()
        thumbnail.snp.updateConstraints { make in make.size.equalTo(compact ? 44 : 64) }
        overlay.layer?.cornerRadius = (compact ? 44 : 64) / 2
    }

    /// Draws the reference's cropped image or its upload and selection decoration.
    override func draw(
        _ dirtyRect: NSRect
    ) {
        let size: CGFloat = compact ? 44 : 64
        let circle = NSRect(
            x: (bounds.width - size) / 2 + 1,
            y: 1,
            width: size - 2,
            height: size - 2
        )
        let outline = NSBezierPath(ovalIn: circle)
        if reference == nil {
            Palette.surface.setFill()
            outline.fill()
            outline.setLineDash(
                [4, 3],
                count: 2,
                phase: 0
            )
            Palette.border.setStroke()
            outline.lineWidth = 2
            outline.stroke()
            Icon.draw(
                .plus,
                in: NSRect(
                    x: bounds.midX - 12,
                    y: size / 2 - 12,
                    width: 24,
                    height: 24
                ),
                color: Palette.secondary
            )
        }
        if !compact {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center

            paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [
                .font: Typography.font(
                    size: 11,
                    weight: selected ? .semibold : .regular
                ),
                .foregroundColor: Palette.secondary.blended(
                    withFraction: min(1, max(0, selectionProgress)),
                    of: Palette.accent
                ) ?? Palette.secondary,
                .paragraphStyle: paragraph,
            ]
            ((reference?.name ?? "Upload") as NSString).draw(
                in: NSRect(
                    x: 0,
                    y: 70,
                    width: bounds.width,
                    height: 14
                ),
                withAttributes: attributes
            )
        }
    }

    /// Updates the existing thumbnail border and upload or retry overlay before drawing.
    override func viewWillDraw() {
        super.viewWillDraw()
        thumbnail.layer?.borderWidth = 2
        let border =
            (selected
            ? Palette.accent
            : hovered && isEnabled
                ? NSColor(
                    srgbRed: 199 / 255,
                    green: 208 / 255,
                    blue: 248 / 255,
                    alpha: 1
                )
                : NSColor(
                    white: 0.95,
                    alpha: 1
                )).cgColor
        ControlMotion.set(
            border,
            for: "borderColor",
            on: thumbnail.layer,
            in: self
        )
        // The overlay lives above the image; changing upload progress never reloads its source.
        let progress = reference?.uploadState == .uploading
        let error = reference?.uploadState == .error
        overlay.isHidden = !progress && !error
        overlay.layer?.cornerRadius = overlay.bounds.height / 2
        let background =
            (error
            ? NSColor(
                srgbRed: 120 / 255,
                green: 20 / 255,
                blue: 20 / 255,
                alpha: 0.65
            ) : .black.withAlphaComponent(0.55)).cgColor
        ControlMotion.set(
            background,
            for: "backgroundColor",
            on: overlay.layer,
            in: self
        )
        progressLabel.stringValue = error ? "Retry" : "\(Int((reference?.uploadProgress ?? 0) * 100))%"
        progressLabel.snp.updateConstraints { make in
            make.centerY.equalToSuperview().offset(error ? 0 : 13)
        }
    }

    /// The noninteractive upload or failure overlay above the thumbnail.
    private lazy var overlay: GenerationReferenceOverlay = {
        let view = GenerationReferenceOverlay()
        return view
    }()

    /// The upload percentage or retry caption shown by the overlay.
    private lazy var progressLabel: NSTextField = {
        let label = makeLabel(
            size: 10,
            color: .white
        )
        label.alignment = .center
        return label
    }()
}

/// A decorative overlay that lets pointer events reach its reference button.
private final class GenerationReferenceOverlay: Canvas {

    /// Lets pointer events reach the native reference control beneath decorative content.
    override func hitTest(
        _ point: NSPoint
    ) -> NSView? { nil }
}
