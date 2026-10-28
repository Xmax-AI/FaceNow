//
//  InputField.swift
//  XmaxCamera
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit

/// A rounded native input with shared colors, optional fixed prefix, and accessory space.
@MainActor
final class InputField: Canvas {

    /// The noneditable leading text, kept outside the field's editable value.
    var prefix: String? {
        didSet {
            prefixLabel.stringValue = prefix ?? ""
            prefixLabel.isHidden = prefix == nil
            separator.isHidden = prefix == nil
            needsLayout = true
        }
    }

    /// The space reserved for a host-owned trailing action inside the input.
    var trailingInset: CGFloat = 0 { didSet { needsLayout = true } }

    /// Whether editing and the fixed-prefix presentation are enabled.
    var isEnabled = true {
        didSet {
            textField.isEnabled = isEnabled
            alphaValue = isEnabled ? 1 : 0.55
        }
    }

    /// Whether the native editor masks its value.
    private let secure: Bool

    /// The last focus state rendered by the shared input surface.
    private var focused = false

    /// The native editor, whose delegate and accessibility label belong to the host.
    private(set) lazy var textField: NSTextField = {
        let field = secure ? NSSecureTextField() : NSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Typography.font(size: 15)
        field.textColor = Palette.text
        return field
    }()

    /// The fixed prefix cannot receive text selection or keyboard edits.
    private lazy var prefixLabel: NSTextField = {
        let label = makeLabel(
            size: 15,
            weight: .medium
        )
        label.isHidden = true
        label.usesSingleLineMode = true
        label.lineBreakMode = .byClipping
        label.alignment = .center
        return label
    }()

    /// Separates fixed prefix text from the editable value.
    private lazy var separator: Canvas = {
        let view = Canvas(color: Palette.border)
        view.isHidden = true
        return view
    }()

    /// Creates a shared input without assigning business validation or delegate behavior.
    init(
        secure: Bool = false
    ) {
        self.secure = secure
        super.init(
            color: Palette.surface,
            radius: 14
        )
        layer?.borderColor = Palette.border.cgColor
        layer?.borderWidth = 1
        [textField, prefixLabel, separator].forEach(addSubview)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(editingBegan),
            name: NSControl.textDidBeginEditingNotification,
            object: textField
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(editingEnded),
            name: NSControl.textDidEndEditingNotification,
            object: textField
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(synchronizeFocus),
            name: NSWindow.didUpdateNotification,
            object: nil
        )
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Removes editing observations when this input is released.
    deinit { NotificationCenter.default.removeObserver(self) }

    /// Centers the editor and reserves prefix and accessory space without changing its value.
    override func layout() {
        super.layout()
        var leading: CGFloat = 20
        if prefix != nil {
            let width = max(76, ceil(prefixLabel.intrinsicContentSize.width) + 40)
            let height = ceil(prefixLabel.intrinsicContentSize.height)
            prefixLabel.frame = NSRect(
                x: 0,
                y: (bounds.height - height) / 2,
                width: width,
                height: height
            )
            separator.frame = NSRect(
                x: prefixLabel.frame.maxX,
                y: (bounds.height - 20) / 2,
                width: 1,
                height: 20
            )
            leading = separator.frame.maxX + 20
        }
        let editorHeight = ceil(textField.intrinsicContentSize.height)
        textField.frame = NSRect(
            x: leading,
            y: (bounds.height - editorHeight) / 2,
            width: max(0, bounds.width - leading - 20 - trailingInset),
            height: editorHeight
        )
    }

    /// Lets the entire enabled input surface focus its native editor.
    override func mouseDown(
        with event: NSEvent
    ) {
        if isEnabled { window?.makeFirstResponder(textField) }
    }

    /// Uses the product accent for a restrained focus border instead of a system bezel ring.
    @objc private func editingBegan() {
        setFocused(true)
    }

    /// Restores the shared neutral input surface when editing ends.
    @objc private func editingEnded() {
        setFocused(false)
    }

    /// Includes focus changes that occur before the user types the first character.
    @objc private func synchronizeFocus(
        _ notification: Notification
    ) {
        guard let window, notification.object as? NSWindow === window else { return }
        setFocused(textField.currentEditor() != nil)
    }

    /// Animates focus colors from their current presentation so rapid focus changes stay smooth.
    private func setFocused(
        _ focused: Bool
    ) {
        guard self.focused != focused, let layer else { return }
        self.focused = focused
        let visible = layer.presentation() ?? layer
        let background = (focused ? NSColor.white : Palette.surface).cgColor
        let border = (focused ? Palette.accent.withAlphaComponent(0.6) : Palette.border).cgColor
        let width: CGFloat = focused ? 1.5 : 1
        let transitions: [(String, Any?, Any)] = [
            ("backgroundColor", visible.backgroundColor, background),
            ("borderColor", visible.borderColor, border),
            ("borderWidth", visible.borderWidth, width),
        ]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = background
        layer.borderColor = border
        layer.borderWidth = width
        CATransaction.commit()
        for (key, start, end) in transitions {
            let animation = CABasicAnimation(keyPath: key)
            animation.fromValue = start
            animation.toValue = end
            animation.duration = 0.3
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: "InputField.\(key)")
        }
    }
}
