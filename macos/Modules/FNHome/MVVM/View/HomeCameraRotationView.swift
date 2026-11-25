//
//  HomeCameraRotationView.swift
//  FaceNow
//

import AppKit
import SnapKit
import XmaxSDK

/// Selects physical camera rotation before capture, independently from the output aspect ratio.
@MainActor
final class HomeCameraRotationView: Canvas {

    private(set) var rotation: CameraRotation = .degrees0
    private var popover: NSPopover?
    private lazy var button: Button = {
        let view = Button("0°", style: .plain)
        view.font = Typography.font(size: 13.5, weight: .medium)
        view.foregroundColor = Palette.videoControlText
        view.restingBackgroundColor = Palette.videoControlSurface
        view.hoverBackgroundColor = Palette.videoControlHover
        view.leadingPadding = 10
        view.trailingPadding = 10
        view.cornerRadius = 17
        view.layer?.cornerRadius = 17
        view.layer?.borderWidth = 1
        view.layer?.borderColor = Palette.videoControlBorder.cgColor
        view.showsShadow = false
        view.toolTip = HomeStrings.cameraRotation
        view.setAccessibilityLabel(HomeStrings.cameraRotation)
        view.onClick = { [weak self] in self?.showPicker() }
        return view
    }()

    var isEnabled = true {
        didSet {
            button.isEnabled = isEnabled
            if !isEnabled { closePicker() }
        }
    }

    init() {
        super.init()
        addSubview(button)
        button.snp.makeConstraints { make in make.edges.equalToSuperview() }
        snp.makeConstraints { make in
            make.width.equalTo(button.preferredWidth)
            make.height.equalTo(34)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func closePicker() {
        popover?.close()
        popover = nil
    }

    private func showPicker() {
        guard isEnabled else { return }
        if popover?.isShown == true { closePicker(); return }
        let card = Canvas(color: NSColor(srgbRed: 0.24, green: 0.24, blue: 0.27, alpha: 0.95), radius: 12)
        card.snp.makeConstraints { make in make.width.equalTo(88) }
        var previous: Button?
        var controls: [Button] = []
        for choice in CameraRotation.allCases {
            let row = HomeRotationChoiceButton(title: "\(choice.rawValue)°", isCurrent: choice == rotation)
            row.font = Typography.font(size: 13.5, weight: .medium)
            row.foregroundColor = .white
            row.cornerRadius = 8
            row.showsShadow = false
            row.restingBackgroundColor = choice == rotation ? .systemBlue : .clear
            row.hoverBackgroundColor = choice == rotation ? .systemBlue : .white.withAlphaComponent(0.12)
            row.alignment = .left
            row.leadingPadding = 26
            row.trailingPadding = 6
            row.setAccessibilityValue(choice == rotation ? GenerationStrings.selected : "")
            row.onClick = { [weak self] in
                guard let self else { return }
                self.rotation = choice
                self.button.title = "\(choice.rawValue)°"
                self.button.setAccessibilityValue(self.button.title)
                self.snp.updateConstraints { make in make.width.equalTo(self.button.preferredWidth) }
                self.closePicker()
                self.window?.makeFirstResponder(self.button)
            }
            card.addSubview(row)
            row.snp.makeConstraints { make in
                make.leading.trailing.equalToSuperview().inset(5)
                make.height.equalTo(28)
                if let previous {
                    make.top.equalTo(previous.snp.bottom).offset(2)
                } else {
                    make.top.equalToSuperview().inset(5)
                }
                if choice == CameraRotation.allCases.last {
                    make.bottom.equalToSuperview().inset(5)
                }
            }
            controls.append(row)
            previous = row
        }
        for (index, control) in controls.enumerated() {
            control.nextKeyView = controls[(index + 1) % controls.count]
        }
        let controller = NSViewController()
        controller.view = card
        let picker = NSPopover()
        picker.behavior = .transient
        picker.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        picker.appearance = NSAppearance(named: .darkAqua)
        picker.contentViewController = controller
        picker.contentSize = NSSize(
            width: 88,
            height: CGFloat(controls.count) * 28 + CGFloat(max(0, controls.count - 1)) * 2 + 10
        )
        popover = picker
        picker.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        picker.contentViewController?.view.window?.makeFirstResponder(
            controls[CameraRotation.allCases.firstIndex(of: rotation) ?? 0]
        )
    }
}

/// Reserves the same checkmark column for every angle, preserving aligned menu labels.
@MainActor
private final class HomeRotationChoiceButton: Button {

    private let isCurrent: Bool

    init(title: String, isCurrent: Bool) {
        self.isCurrent = isCurrent
        super.init(title, style: .plain)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isCurrent else { return }
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 7, y: bounds.midY))
        path.line(to: NSPoint(x: 10, y: bounds.midY + 3))
        path.line(to: NSPoint(x: 16, y: bounds.midY - 4))
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        NSColor.white.setStroke()
        path.stroke()
    }
}
