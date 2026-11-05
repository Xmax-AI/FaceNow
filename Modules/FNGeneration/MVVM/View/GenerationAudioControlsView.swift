//
//  GenerationAudioControlsView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import Combine
import SnapKit

/// Aligns microphone selection and input strength with the trailing audio and video adjustments action.
@MainActor
final class GenerationAudioControlsView: Canvas {

    /// The matching space around all four edges of the audio toolbar.
    private static let contentInset: CGFloat = 8

    /// The complete row height shared by workspace measurement and native constraints.
    static let preferredHeight = ToolbarControlMetrics.compactHeight + 2 * contentInset

    /// Derives presentation from the shared generation state.
    private let viewModel = GenerationAudioControlsViewModel()

    /// Selects physical microphone input through the existing native device list.
    private lazy var microphonePicker: HomeInputPickerView = {
        let view = HomeInputPickerView(input: .microphone, presentation: .toolbar)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        return view
    }()

    /// Displays live input strength beside the selected microphone.
    private lazy var inputLevel: GenerationInputLevelView = {
        let view = GenerationInputLevelView()
        return view
    }()

    /// Updates only the meter without refreshing the workspace's other controls.
    private var levelObservation: AnyCancellable?

    /// Finishes hiding the entire indicator after its shared opacity transition.
    private var levelDismissal: Task<Void, Never>?

    /// Opens the audio synchronization design in a native popover.
    private lazy var adjustmentButton: ToolbarButton = {
        let view = ToolbarButton(
            GenerationStrings.audioVideoAdjustments,
            style: .plain,
            weight: .semibold
        )
        view.symbolName = "slider.horizontal.3"
        view.foregroundColor = Palette.accent
        view.restingBackgroundColor = Palette.accent.withAlphaComponent(0.12)
        view.hoverBackgroundColor = Palette.accent.withAlphaComponent(0.18)
        view.trailingPadding = ToolbarControlMetrics.trailingPadding
        view.cornerRadius = 16
        view.centersTitleVisually = true
        view.setAccessibilityLabel(GenerationStrings.audioVideoAdjustments)
        view.onClick = { [weak self] in self?.showAdjustments() }
        return view
    }()

    /// Retains only the currently displayed transient settings card.
    private var adjustmentPopover: NSPopover?

    /// Installs one stable constraint graph with shared control height and centerline.
    init() {
        super.init(color: .white, radius: 16)
        layer?.borderWidth = 1
        layer?.borderColor = Palette.border.cgColor
        [microphonePicker, inputLevel, adjustmentButton].forEach(addSubview)
        microphonePicker.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.contentInset)
            make.top.bottom.equalToSuperview().inset(Self.contentInset)
        }
        inputLevel.snp.makeConstraints { make in
            make.leading.equalTo(microphonePicker.snp.trailing).offset(20)
            make.centerY.equalTo(microphonePicker)
            make.height.equalTo(microphonePicker)
            make.width.equalTo(220).priority(490)
            make.width.greaterThanOrEqualTo(160)
            make.trailing.lessThanOrEqualTo(adjustmentButton.snp.leading).offset(-20)
        }
        adjustmentButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(Self.contentInset)
            make.top.bottom.equalTo(microphonePicker)
            make.width.equalTo(adjustmentButton.preferredWidth)
        }
        levelObservation = viewModel.microphoneLevels.removeDuplicates().sink { [weak self] level in
            self?.inputLevel.update(level: level)
        }
        update()
    }

    /// Storyboard decoding is unsupported for this programmatic toolbar.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Reflects selection and adjustment availability independently of meter updates.
    func update() {
        microphonePicker.update()
        updateInputLevelVisibility()
        adjustmentButton.isEnabled = viewModel.canAdjust
        if !viewModel.canAdjust { closePopovers() }
    }

    /// Reveals the title and meter together only while a microphone is selected.
    private func updateInputLevelVisibility() {
        let visible = viewModel.showsInputLevel
        let opacity: CGFloat = visible ? 1 : 0
        guard inputLevel.alphaValue != opacity else { return }
        levelDismissal?.cancel()
        levelDismissal = nil
        inputLevel.setAccessibilityElement(visible)
        if visible { inputLevel.isHidden = false }
        ControlMotion.setOpacity(opacity, on: inputLevel)
        guard !visible else { return }
        guard ControlMotion.isAnimated(in: inputLevel), !isHiddenOrHasHiddenAncestor else {
            inputLevel.isHidden = true
            return
        }
        levelDismissal = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(ControlMotion.duration)) } catch { return }
            guard let self, !self.viewModel.showsInputLevel else { return }
            self.inputLevel.isHidden = true
            self.levelDismissal = nil
        }
    }

    /// Releases device and adjustment menus before page navigation or teardown.
    func closePopovers() {
        microphonePicker.closePicker()
        adjustmentPopover?.close()
        adjustmentPopover = nil
    }

    /// Closes transient menus when the workspace is hidden.
    override func viewDidHide() {
        super.viewDidHide()
        closePopovers()
    }

    /// Closes transient menus when the toolbar leaves its native window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { closePopovers() }
    }

    /// Opens a single native settings card without changing any effect or audio intent.
    private func showAdjustments() {
        if adjustmentPopover?.isShown == true {
            closePopovers()
            return
        }
        guard viewModel.canAdjust, window != nil, !isHiddenOrHasHiddenAncestor else { return }
        microphonePicker.closePicker()
        let content = GenerationAdjustmentPopoverView()
        content.onClose = { [weak self] in self?.closePopovers() }
        let controller = NSViewController()
        controller.view = content
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = controller
        popover.contentSize = content.fittingSize
        adjustmentPopover = popover
        popover.show(relativeTo: adjustmentButton.bounds, of: adjustmentButton, preferredEdge: .maxY)
    }
}

/// Shows physical microphone input as a title followed by eight equal green segments.
@MainActor
private final class GenerationInputLevelView: Canvas {

    /// Names the read-only input activity indicator.
    private lazy var titleLabel: NSTextField = {
        let view = NSTextField(labelWithString: GenerationStrings.inputLevel)
        view.font = .systemFont(ofSize: 13, weight: .semibold)
        view.textColor = Palette.softText
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        view.setAccessibilityElement(false)
        return view
    }()

    /// Clips the ends of the segmented track to the existing rounded shape.
    private lazy var track: Canvas = {
        let view = Canvas(radius: 4)
        view.layer?.masksToBounds = true
        return view
    }()

    /// The fixed segment cells used for both layout and normalized strength updates.
    private let segments: [Canvas] = (0..<8).map { _ in Canvas(color: Palette.border) }

    /// Creates a horizontal meter whose title and track share the toolbar's vertical center.
    init() {
        super.init()
        toolTip = GenerationStrings.inputLevelHelp
        setAccessibilityElement(true)
        setAccessibilityRole(.levelIndicator)
        setAccessibilityLabel(GenerationStrings.inputLevel)
        setAccessibilityHelp(GenerationStrings.inputLevelHelp)
        setAccessibilityMinValue(0)
        setAccessibilityMaxValue(100)
        [titleLabel, track].forEach(addSubview)
        titleLabel.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
        }
        track.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel.snp.trailing).offset(8)
            make.trailing.centerY.equalToSuperview()
            make.height.equalTo(8)
        }
        var previous: Canvas?
        for segment in segments {
            track.addSubview(segment)
            segment.snp.makeConstraints { make in
                make.top.bottom.equalToSuperview()
                if let previous {
                    make.leading.equalTo(previous.snp.trailing).offset(2)
                    make.width.equalTo(previous)
                } else {
                    make.leading.equalToSuperview()
                }
            }
            previous = segment
        }
        previous?.snp.makeConstraints { make in make.trailing.equalToSuperview() }
        update(level: nil)
    }

    /// Storyboard decoding is unsupported for this read-only indicator.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Updates the lit segment count using the normalized SDK reading and shared appearance transition.
    func update(
        level: Float?
    ) {
        let value = level.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil } ?? 0
        let count = Int(ceil(value * Float(segments.count)))
        for (index, segment) in segments.enumerated() {
            let color: NSColor = index < count ? .systemGreen : Palette.border
            ControlMotion.set(
                color.cgColor,
                for: "backgroundColor",
                on: segment.layer,
                in: self
            )
        }
        setAccessibilityValue(Int((value * 100).rounded()))
    }
}
