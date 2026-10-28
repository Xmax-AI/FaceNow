//
//  TabSwitcher.swift
//  XmaxCamera
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit

/// A shared pill-shaped tab group with persistent native buttons and product typography.
@MainActor
final class TabSwitcher: Canvas {

    /// The horizontal sizing policy for the tab buttons.
    enum Distribution {

        /// Divides the available width equally between all tabs.
        case equal

        /// Sizes each tab to its title and the shared horizontal padding.
        case content
    }

    /// The selected tab, or nil when an alternate input mode is presented.
    var selectedIndex: Int? = 0 { didSet { updateButtons() } }

    /// Whether the group accepts selection changes without losing per-tab availability.
    var isEnabled = true { didSet { updateButtons() } }

    /// Reports user selections; programmatic updates never invoke this callback.
    var onSelectionChanged: ((Int) -> Void)?

    /// The labels retained for the lifetime of this group.
    private let titles: [String]

    /// The sizing policy shared by layout and preferred-width measurement.
    private let distribution: Distribution

    /// The tabs permitted by the host, independently of the group's busy state.
    private var enabledIndices: Set<Int>

    /// The persistent native buttons sharing the generation-page tab appearance.
    private lazy var buttons: [Button] = {
        let buttons = titles.enumerated().map { index, title in
            let button = Button(
                title,
                style: .tab
            )
            button.font = Typography.font(
                size: 13.5,
                weight: .medium
            )
            button.tracking = 0.135
            button.leadingPadding = 22
            button.trailingPadding = 22
            button.onClick = { [weak self] in self?.select(index) }
            return button
        }
        return buttons
    }()

    /// Creates a tab group without taking ownership of business selection state.
    init(
        titles: [String],
        distribution: Distribution = .equal
    ) {
        self.titles = titles
        self.distribution = distribution
        self.enabledIndices = Set(titles.indices)
        super.init(
            color: NSColor(
                srgbRed: 120 / 255,
                green: 120 / 255,
                blue: 128 / 255,
                alpha: 0.1
            ),
            radius: 21
        )
        buttons.forEach(addSubview)
        updateButtons()
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// The natural width including four-point insets and two-point tab spacing.
    var preferredWidth: CGFloat {
        let widths = buttons.map(\.preferredWidth)
        let contentWidth =
            distribution == .equal
            ? (widths.max() ?? 0) * CGFloat(widths.count)
            : widths.reduce(
                0,
                +
            )
        return contentWidth + CGFloat(max(0, widths.count - 1)) * 2 + 8
    }

    /// The shared tab height including its background insets.
    override var fittingSize: NSSize {
        NSSize(
            width: preferredWidth,
            height: 42
        )
    }

    /// Updates a tab's availability while retaining its selection and native identity.
    func setEnabled(
        _ enabled: Bool,
        at index: Int
    ) {
        guard buttons.indices.contains(index) else { return }
        if enabled { enabledIndices.insert(index) } else { enabledIndices.remove(index) }
        updateButtons()
    }

    /// Applies the sizing policy within the shared rounded background.
    override func layout() {
        super.layout()
        guard !buttons.isEmpty else { return }
        let available = max(0, bounds.width - 8 - CGFloat(buttons.count - 1) * 2)
        let naturalWidth = buttons.map(\.preferredWidth).reduce(
            0,
            +
        )
        let scale = naturalWidth > 0 ? min(1, available / naturalWidth) : 1
        var x: CGFloat = 4
        for button in buttons {
            let width =
                distribution == .equal ? available / CGFloat(buttons.count) : button.preferredWidth * scale
            button.frame = NSRect(
                x: x,
                y: 4,
                width: width,
                height: max(0, bounds.height - 8)
            )
            x += width + 2
        }
    }

    /// Accepts only enabled user changes and leaves business routing to the host.
    private func select(
        _ index: Int
    ) {
        guard isEnabled, enabledIndices.contains(index), selectedIndex != index else { return }
        selectedIndex = index
        onSelectionChanged?(index)
    }

    /// Refreshes visual selection, accessibility values, and effective availability.
    private func updateButtons() {
        for (index, button) in buttons.enumerated() {
            button.selected = selectedIndex == index
            button.isEnabled = isEnabled && enabledIndices.contains(index)
            button.setAccessibilityValue(button.selected ? "Selected" : "")
        }
    }
}
