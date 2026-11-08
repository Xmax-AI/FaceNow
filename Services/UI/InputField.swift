//
//  InputField.swift
//  FaceNow
//

import AppKit
import CoreText
import SnapKit

/// A rounded native input with shared colors, optional fixed prefix, and accessory space.
@MainActor
final class InputField: Canvas {

    /// The noneditable leading text, kept outside the field's editable value.
    var prefix: String? {
        didSet {
            guard prefix != oldValue else { return }
            prefixLabel.stringValue = prefix ?? ""
            updatePrefixConstraints()
        }
    }

    /// The space reserved for a host-owned trailing action inside the input.
    var trailingInset: CGFloat = 0 {
        didSet { editorTrailing?.update(inset: 20 + trailingInset) }
    }

    /// The host-selected editor font, also sizing the regular-weight fixed prefix.
    var font: NSFont = Typography.font(size: 15) {
        didSet {
            textField.font = font
            textField.currentEditor()?.font = font
            prefixLabel.font = Typography.font(
                size: font.pointSize,
                weight: .regular
            )
            needsLayout = true
        }
    }

    /// Whether editing and the fixed-prefix presentation are enabled.
    var isEnabled = true {
        didSet {
            textField.isEnabled = isEnabled
            ControlMotion.setOpacity(
                isEnabled ? 1 : 0.55,
                on: self
            )
        }
    }

    /// Keeps a rejected value visibly invalid until its owner clears validation after an edit.
    var validationMessage: String? {
        didSet {
            guard validationMessage != oldValue else { return }
            toolTip = validationMessage
            textField.toolTip = validationMessage
            textField.setAccessibilityHelp(validationMessage)
            updateAppearance()
            if oldValue == nil, validationMessage != nil {
                ControlMotion.shake(self)
            }
        }
    }

    /// Whether the native editor masks its value.
    private let secure: Bool

    /// The last focus state rendered by the shared input surface.
    private var focused = false

    /// Keeps keyboard-focus presentation exclusive even before native text editing begins.
    private static weak var focusedInput: InputField?

    /// The editor's leading edge while no fixed prefix is shown.
    private var plainLeading: Constraint?

    /// The editor's leading edge after the visible prefix separator.
    private var prefixedLeading: Constraint?

    /// The trailing constraint reserves space for a host-owned accessory.
    private var editorTrailing: Constraint?

    /// The separator's inset from the prefix region's trailing edge, in points.
    private let prefixSeparatorInset: CGFloat = 2

    /// The last native-editor offset applied for matching visible spacing across the separator.
    private var prefixEditorOffset: CGFloat?

    /// The fixed prefix owns its horizontal padding independently of the editable value.
    private lazy var prefixRegion: Canvas = {
        let view = Canvas()
        view.isHidden = true
        return view
    }()

    /// The native editor, whose delegate and accessibility label belong to the host.
    private(set) lazy var textField: NSTextField = {
        let reportFocus: () -> Void = { [weak self] in self?.setFocused(true) }
        let field: NSTextField
        if secure {
            let editor = FocusSecureTextField()
            editor.onFocus = reportFocus
            field = editor
        } else {
            let editor = FocusTextField()
            editor.onFocus = reportFocus
            field = editor
        }
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = font
        field.textColor = Palette.text
        return field
    }()

    /// The fixed prefix cannot receive text selection or keyboard edits.
    private lazy var prefixLabel: InputPrefixView = {
        let label = InputPrefixView()
        label.font = Typography.font(
            size: font.pointSize,
            weight: .regular
        )
        label.setContentHuggingPriority(
            .defaultHigh,
            for: .horizontal
        )
        label.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
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
            color: Palette.inputSurface,
            radius: 12
        )
        layer?.borderColor = Palette.border.cgColor
        layer?.borderWidth = 1
        [textField, prefixRegion, separator].forEach(addSubview)
        prefixRegion.addSubview(prefixLabel)
        configureLayout()
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
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Removes editing observations when this input is released.
    deinit { NotificationCenter.default.removeObserver(self) }

    /// Tracks responder changes that do not produce a native end-editing notification.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didUpdateNotification,
            object: nil
        )
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(synchronizeFocus),
                name: NSWindow.didUpdateNotification,
                object: window
            )
        } else {
            ControlMotion.stopShake(in: self)
        }
        synchronizeFocus()
    }

    /// Clears retained focus decoration when an input mode or its owning page is hidden.
    override func viewDidHide() {
        super.viewDidHide()
        ControlMotion.stopShake(in: self)
        setFocused(false)
    }

    /// Constrains the native editor and independent prefix region without assigning child frames.
    private func configureLayout() {
        prefixRegion.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.greaterThanOrEqualTo(64)
            make.width.equalTo(prefixLabel.snp.width).offset(32)
        }
        prefixLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.bottom.equalToSuperview()
        }
        separator.snp.makeConstraints { make in
            // Tighten the trailing gap without shifting the country code's leading inset.
            make.leading.equalTo(prefixRegion.snp.trailing).offset(-prefixSeparatorInset)
            make.centerY.equalToSuperview()
            make.width.equalTo(1)
            make.height.equalTo(20)
        }
        textField.snp.makeConstraints { make in
            plainLeading = make.leading.equalToSuperview().offset(20).constraint
            editorTrailing = make.trailing.equalToSuperview().inset(20 + trailingInset).constraint
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview()
            make.bottom.lessThanOrEqualToSuperview()
        }
        textField.snp.prepareConstraints { make in
            prefixedLeading = make.leading.equalTo(separator.snp.trailing).offset(20).constraint
        }
        updatePrefixConstraints()
    }

    /// Matches the visible text gaps while accounting for the native cell's own horizontal inset.
    override func layout() {
        super.layout()
        guard prefix != nil, prefixRegion.bounds.width > 0 else { return }
        let prefixGap = (prefixRegion.bounds.width - prefixLabel.inkWidth) / 2 - prefixSeparatorInset
        let cellInset = textField.cell?.drawingRect(forBounds: textField.bounds).minX ?? 0
        let offset = max(0, prefixGap - cellInset)
        guard prefixEditorOffset != offset else { return }
        prefixEditorOffset = offset
        prefixedLeading?.update(offset: offset)
    }

    /// Switches only the leading relationship when the host changes input mode.
    private func updatePrefixConstraints() {
        let showsPrefix = prefix != nil
        prefixRegion.isHidden = !showsPrefix
        separator.isHidden = !showsPrefix
        if showsPrefix {
            plainLeading?.deactivate()
            prefixedLeading?.activate()
        } else {
            prefixedLeading?.deactivate()
            plainLeading?.activate()
        }
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

    /// Resolves the actual field-editor owner instead of retaining an earlier focus callback.
    @objc private func synchronizeFocus() {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor, isEnabled else {
            setFocused(false)
            return
        }
        let responder = window.firstResponder
        let editor = responder as? NSTextView
        setFocused(responder === textField || editor?.delegate === textField)
    }

    /// Animates focus colors from their current presentation so rapid focus changes stay smooth.
    private func setFocused(
        _ focused: Bool
    ) {
        let focused = focused && window?.isKeyWindow == true && !isHiddenOrHasHiddenAncestor && isEnabled
        if focused {
            if let previous = Self.focusedInput, previous !== self {
                previous.setFocused(false)
            }
            Self.focusedInput = self
        } else if Self.focusedInput === self {
            Self.focusedInput = nil
        }
        guard self.focused != focused else { return }
        self.focused = focused
        updateAppearance()
    }

    /// Gives field validation priority over focus without changing native editing or text colors.
    private func updateAppearance() {
        guard let layer else { return }
        let invalid = validationMessage != nil
        let background = (focused ? NSColor.white : Palette.inputSurface).cgColor
        let border = (invalid ? Palette.destructive : focused ? Palette.accent.withAlphaComponent(0.6) : Palette.border)
            .cgColor
        let width: CGFloat = focused || invalid ? 1.5 : 1
        let transitions: [(String, Any)] = [
            ("backgroundColor", background),
            ("borderColor", border),
            ("borderWidth", width),
        ]
        for (key, value) in transitions {
            ControlMotion.set(
                value,
                for: key,
                on: layer,
                in: self
            )
        }
    }
}

/// Centers the noneditable prefix's visible glyphs independently of native editor baseline metrics.
@MainActor
private final class InputPrefixView: Canvas {

    /// The country code displayed without becoming part of the editable phone number.
    var stringValue = "" {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    /// The shared application font used for both measurement and drawing.
    var font = Typography.font(size: 15, weight: .regular) {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    /// The native text line preserves the bundled font's actual glyph shapes.
    private var textLine: CTLine {
        CTLineCreateWithAttributedString(
            NSAttributedString(
                string: stringValue,
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): Palette.text.cgColor,
                ]
            )
        )
    }

    /// The visible glyph width used to match the editor's spacing across the separator.
    var inkWidth: CGFloat { CTLineGetBoundsWithOptions(textLine, .useGlyphPathBounds).width }

    /// Supplies the glyph width to the prefix region's content and padding constraints.
    override var intrinsicContentSize: NSSize {
        let ink = CTLineGetBoundsWithOptions(textLine, .useGlyphPathBounds)
        return NSSize(width: ceil(ink.width), height: ceil(ink.height))
    }

    /// Draws the actual glyph bounds at the region's optical center without a fixed offset.
    override func draw(
        _ dirtyRect: NSRect
    ) {
        guard let context = NSGraphicsContext.current?.cgContext, !stringValue.isEmpty else { return }
        let line = textLine
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: bounds.midX - ink.midX, y: bounds.midY - ink.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// Passes pointer events through to the input surface and its native editor.
    override func hitTest(
        _ point: NSPoint
    ) -> NSView? { nil }
}

/// Reports native focus before any text changes while retaining the normal field editor.
@MainActor
private final class FocusTextField: NSTextField {

    /// Updates the surrounding input surface after native focus succeeds.
    var onFocus: (() -> Void)?

    /// Starts the input transition when the field gains keyboard focus.
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }
}

/// Keeps secure editing intact while reporting focus before a key is typed.
@MainActor
private final class FocusSecureTextField: NSSecureTextField {

    /// Updates the surrounding input surface after native focus succeeds.
    var onFocus: (() -> Void)?

    /// Starts the input transition without changing secure field-editor behavior.
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }
}
