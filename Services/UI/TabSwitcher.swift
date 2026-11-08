//
//  TabSwitcher.swift
//  FaceNow
//

import AppKit
import CoreText
import SnapKit

/// Owns selection and one exclusive hover target independently of the shared Button control.
@MainActor
final class TabSwitcher: Canvas {

    /// The neutral track color, also used by resting segments.
    fileprivate static let trackColor = NSColor(
        srgbRed: 0.9 + 0.1 * 120 / 255,
        green: 0.9 + 0.1 * 120 / 255,
        blue: 0.9 + 0.1 * 128 / 255,
        alpha: 1
    )

    /// The surface and selection colors used by the segment group.
    enum Style {
        case light
        case videoOverlay
    }

    /// The horizontal sizing policy for the segment controls.
    enum Distribution {

        /// Divides the available width equally between all segments.
        case equal

        /// Sizes each segment to its title and horizontal padding.
        case content
    }

    /// The selected segment; selection never changes in response to hover.
    var selectedIndex: Int? = 0 {
        didSet { if selectedIndex != oldValue { updateSegments() } }
    }

    /// Whether the group accepts selection changes.
    var isEnabled = true {
        didSet { if isEnabled != oldValue { updateSegments() } }
    }

    /// Reports explicit user selections without replaying programmatic updates.
    var onSelectionChanged: ((Int) -> Void)?

    /// An optional compact radius; nil uses the existing capsule shape.
    var cornerRadius: CGFloat? { didSet { needsLayout = true } }

    /// The content inset on each side of a label, preserving the default generation-mode spacing.
    var horizontalPadding: CGFloat = 22 {
        didSet {
            segments.forEach { $0.horizontalPadding = max(0, horizontalPadding) }
            needsLayout = true
        }
    }

    /// The host-selected font shared by segment labels and their width measurements.
    var font: NSFont = Typography.font(size: 13.5, weight: .medium) {
        didSet {
            segments.forEach { $0.applyFont(font) }
            needsLayout = true
        }
    }

    /// The stable labels retained by the native controls.
    private let titles: [String]

    /// The sizing policy shared by measurement and constraints.
    private let distribution: Distribution

    /// The appearance shared by the track and all segments.
    private let style: Style

    /// Per-segment availability supplied by the host.
    private var enabledIndices: Set<Int>

    /// The only segment allowed to render a hover state.
    private var hoveredIndex: Int?

    /// Native controls preserve keyboard focus, click handling, and accessibility.
    private lazy var segments: [TabSegmentButton] = {
        titles.enumerated().map { index, title in
            let segment = TabSegmentButton(title: title, style: style)
            segment.horizontalPadding = max(0, horizontalPadding)
            segment.applyFont(font)
            segment.onSelect = { [weak self] in self?.select(index) }
            segment.onPointerEvent = { [weak self] event in
                self?.updateHover(at: event.locationInWindow)
            }
            return segment
        }
    }()

    /// The content-derived width including the track insets and segment gaps.
    var preferredWidth: CGFloat {
        let widths = segments.map(\.preferredWidth)
        let content =
            distribution == .equal
            ? (widths.max() ?? 0) * CGFloat(widths.count)
            : widths.reduce(0, +)
        return content + CGFloat(max(0, widths.count - 1)) * 2 + 8
    }

    /// The controls used by the onboarding dialog's existing keyboard focus cycle.
    var selectionControls: [NSControl] { segments }

    /// The standard control height and its content-derived width.
    override var fittingSize: NSSize { NSSize(width: preferredWidth, height: 42) }

    /// Composes independently rendered native segments with stable SnapKit constraints.
    init(
        titles: [String],
        distribution: Distribution = .equal,
        style: Style = .light
    ) {
        self.titles = titles
        self.distribution = distribution
        self.style = style
        enabledIndices = Set(titles.indices)
        super.init(color: style == .videoOverlay ? Palette.videoControlSurface : Self.trackColor, radius: 21)
        if style == .videoOverlay {
            layer?.borderWidth = 1
            layer?.borderColor = Palette.videoControlBorder.cgColor
        }
        segments.forEach(addSubview)
        var previous: TabSegmentButton?
        for segment in segments {
            segment.snp.makeConstraints { make in
                make.top.bottom.equalToSuperview().inset(4)
                if let previous {
                    make.leading.equalTo(previous.snp.trailing).offset(2)
                    if distribution == .equal { make.width.equalTo(previous) }
                } else {
                    make.leading.equalToSuperview().offset(4)
                }
                if segment === segments.last { make.trailing.equalToSuperview().inset(4) }
                if distribution == .content { make.width.equalTo(segment.preferredWidth).priority(490) }
            }
            previous = segment
        }
        updateSegments()
    }

    /// Storyboard decoding is unsupported for this programmatic control.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Updates availability without restarting unchanged appearance animations.
    func setEnabled(
        _ enabled: Bool,
        at index: Int
    ) {
        guard segments.indices.contains(index), enabledIndices.contains(index) != enabled else { return }
        if enabled { enabledIndices.insert(index) } else { enabledIndices.remove(index) }
        updateSegments()
    }

    /// Updates content widths before the shared layout pass and applies corner geometry afterward.
    override func layout() {
        if distribution == .content {
            let available = max(0, bounds.width - 8 - CGFloat(max(0, segments.count - 1)) * 2)
            let natural = segments.map(\.preferredWidth).reduce(0, +)
            let scale = natural > 0 ? min(1, available / natural) : 1
            for segment in segments {
                segment.snp.updateConstraints { make in
                    make.width.equalTo(segment.preferredWidth * scale).priority(490)
                }
            }
        }
        super.layout()
        layer?.cornerRadius = min(bounds.height / 2, cornerRadius ?? bounds.height / 2)
        for segment in segments {
            segment.surfaceRadius = cornerRadius.map { max(0, $0 - 4) }
        }
        updateHover()
    }

    /// Clears a retained page's hover when it leaves the window or becomes hidden.
    override func viewDidHide() {
        super.viewDidHide()
        setHoveredIndex(nil)
    }

    /// Rechecks the actual pointer target after mounting or detaching the group.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateHover()
    }

    /// Uses the window's topmost native hit target, excluding overlays and other segments.
    private func updateHover(
        at eventPoint: NSPoint? = nil
    ) {
        guard isEnabled, !isHiddenOrHasHiddenAncestor, let window, window.isVisible,
            let content = window.contentView
        else {
            setHoveredIndex(nil)
            return
        }
        let location = eventPoint ?? window.mouseLocationOutsideOfEventStream
        let point = content.superview?.convert(location, from: nil) ?? location
        let target = content.hitTest(point)
        let index = segments.firstIndex { segment in
            segment.isEnabled && (target === segment || target?.isDescendant(of: segment) == true)
        }
        setHoveredIndex(index)
    }

    /// Applies all segment hover states in one transaction, independently of selection.
    private func setHoveredIndex(
        _ index: Int?
    ) {
        guard hoveredIndex != index else { return }
        hoveredIndex = index
        updateSegments()
    }

    /// Publishes an enabled click while keeping hover from changing the selected segment.
    private func select(
        _ index: Int
    ) {
        guard isEnabled, enabledIndices.contains(index), selectedIndex != index else { return }
        selectedIndex = index
        onSelectionChanged?(index)
    }

    /// Sends explicit selection, hover, and availability to each independently rendered segment.
    private func updateSegments() {
        for (index, segment) in segments.enumerated() {
            segment.update(
                selected: selectedIndex == index,
                hovered: hoveredIndex == index,
                enabled: isEnabled && enabledIndices.contains(index)
            )
        }
    }
}

/// Renders one segment with native layers, without the shared Button's drawing or animation state.
@MainActor
private final class TabSegmentButton: NSButton {

    /// Requests selection through the owning group.
    var onSelect: (() -> Void)?

    /// Sends every native tracking event to the group's sole hit-test function.
    var onPointerEvent: ((NSEvent) -> Void)?

    /// The optional compact segment radius supplied by the group.
    var surfaceRadius: CGFloat? {
        didSet { if surfaceRadius != oldValue { needsLayout = true } }
    }

    /// The persistent background and selection shadow.
    private let surface = CALayer()

    /// The persistent label whose foreground transitions independently of background colors.
    private let label = CATextLayer()

    /// The track's appearance for idle, hovered, and selected states.
    private let style: TabSwitcher.Style

    /// The native pointer area for this segment only.
    private var hoverArea: NSTrackingArea?

    /// The explicit selection state supplied by the group.
    private var selected = false

    /// The explicit hover state supplied by the group.
    private var hovered = false

    /// Whether a native mouse click is currently tracking.
    private var pressed = false

    /// The content inset supplied by the owning tab group.
    var horizontalPadding: CGFloat = 22

    /// The natural label width including the group's horizontal padding.
    var preferredWidth: CGFloat {
        ceil(Typography.size(title, font: font ?? Typography.font(size: 13.5)).width) + horizontalPadding * 2
    }

    /// The focus ring follows the control's constrained bounds.
    override var focusRingMaskBounds: NSRect { bounds }

    /// Installs native click behavior and isolated background and label layers.
    init(
        title: String,
        style: TabSwitcher.Style
    ) {
        self.style = style
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(selectSegment)
        wantsLayer = true
        focusRingType = .exterior
        surface.shadowColor = NSColor.black.cgColor
        surface.shadowRadius = 4
        surface.shadowOffset = CGSize(width: 0, height: 2)
        label.string = title
        label.alignmentMode = .center
        label.truncationMode = .end
        layer?.addSublayer(surface)
        layer?.addSublayer(label)
        updateAppearance()
    }

    /// Storyboard decoding is unsupported for this programmatic control.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Uses the supplied typography for both layer rendering and content measurement.
    func applyFont(
        _ font: NSFont
    ) {
        self.font = font
        label.font = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        label.fontSize = font.pointSize
        needsLayout = true
    }

    /// Applies committed state while keeping selected segments independent of hover.
    func update(
        selected: Bool,
        hovered: Bool,
        enabled: Bool
    ) {
        self.selected = selected
        self.hovered = hovered && enabled && !selected
        isEnabled = enabled
        state = selected ? .on : .off
        setAccessibilityValue(
            selected ? Localization.string("state.selected", table: "Common", defaultValue: "Selected") : ""
        )
        updateAppearance()
    }

    /// Replaces only this segment's native tracking area when its visible bounds change.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        hoverArea = area
    }

    /// Forwards pointer entry directly to the group.
    override func mouseEntered(
        with event: NSEvent
    ) { onPointerEvent?(event) }

    /// Forwards pointer movement directly to the group.
    override func mouseMoved(
        with event: NSEvent
    ) { onPointerEvent?(event) }

    /// Recomputes the actual pointer target when leaving this segment.
    override func mouseExited(
        with event: NSEvent
    ) { onPointerEvent?(event) }

    /// Preserves native click tracking while providing a neutral pressed appearance.
    override func mouseDown(
        with event: NSEvent
    ) {
        guard isEnabled else { return }
        pressed = true
        updateAppearance()
        defer {
            pressed = false
            updateAppearance()
        }
        super.mouseDown(with: event)
    }

    /// Lets AppKit retain native keyboard and accessibility activation.
    @objc private func selectSegment() { onSelect?() }

    /// Keeps AppKit from drawing a second bezel or title over the dedicated layers.
    override func draw(
        _ dirtyRect: NSRect
    ) {}

    /// Supplies the native focus ring without drawing another visual surface.
    override func drawFocusRingMask() {
        let radius = surfaceRadius ?? bounds.height / 2
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }

    /// Updates layer geometry only; SnapKit exclusively positions this NSView.
    override func layout() {
        super.layout()
        let font = font ?? Typography.font(size: 13.5)
        let height = ceil(font.ascender - font.descender + font.leading)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surface.frame = bounds
        surface.cornerRadius = min(bounds.height / 2, surfaceRadius ?? bounds.height / 2)
        surface.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: surface.cornerRadius,
            cornerHeight: surface.cornerRadius,
            transform: nil
        )
        label.contentsScale = window?.backingScaleFactor ?? 2
        label.frame = CGRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
        CATransaction.commit()
    }

    /// Animates independent layer properties from their presentation values through shared timing.
    private func updateAppearance() {
        let background: NSColor
        let foreground: NSColor
        switch style {
        case .light:
            if pressed {
                background = NSColor(white: selected ? 0.98 : 0.94, alpha: 1)
            } else {
                background = selected ? .white : hovered ? NSColor(white: 0.985, alpha: 1) : TabSwitcher.trackColor
            }
            foreground = selected || hovered ? Palette.text : Palette.secondary
        case .videoOverlay:
            if selected {
                background = NSColor(white: pressed ? 0.32 : 0.27, alpha: 1)
            } else {
                background = pressed ? .white.withAlphaComponent(0.15) : hovered ? Palette.videoControlHover : .clear
            }
            foreground = selected || hovered ? .white : Palette.videoControlText
        }
        ControlMotion.set(background.cgColor, for: "backgroundColor", on: surface, in: self)
        ControlMotion.set(foreground.cgColor, for: "foregroundColor", on: label, in: self)
        ControlMotion.set(selected ? Float(0.1) : Float(0), for: "shadowOpacity", on: surface, in: self)
        ControlMotion.setOpacity(isEnabled ? 1 : 0.5, on: self)
    }
}
