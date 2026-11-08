//
//  Icon.swift
//  FaceNow
//

import AppKit

/// Draws the existing Web icon coordinates directly into the AppKit graphics context.
@MainActor
enum Icon {

    /// The vector glyphs supported by the shared native controls.
    enum Kind: Equatable {

        /// The display glyph representing virtual camera and microphone devices.
        case display

        /// The physical or virtual camera glyph.
        case camera

        /// The microphone input glyph.
        case microphone

        /// The diagnostic statistics glyph.
        case statistics

        /// The muted remote-playback glyph.
        case muted

        /// The higher remote-playback volume glyph.
        case volume

        /// The lower remote-playback volume glyph.
        case volumeLow

        /// The frame-interpolation action glyph.
        case lightning

        /// The reference-image upload glyph.
        case plus

        /// The reference dismissal glyph.
        case close

        /// The prompt-submission glyph.
        case arrow

        /// The product website glyph.
        case globe

        /// The X social-profile glyph.
        case socialX

        /// The WeChat follow glyph.
        case
            wechat

        /// The runtime API-key editor glyph.
        case key

        /// The session-stop glyph.
        case stop
    }

    /// Draws a vector glyph in the supplied AppKit rectangle and foreground color.
    static func draw(
        _ kind: Kind,
        in rect: CGRect,
        color: NSColor
    ) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(
            x: rect.minX,
            y: rect.minY
        )
        context.scaleBy(
            x: rect.width / 24,
            y: rect.height / 24
        )
        context.addPath(path(kind))
        context.setFillColor(color.cgColor)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(strokeWidth(for: kind))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if isFilled(kind) {
            context.drawPath(using: .eoFill)
        } else {
            context.strokePath()
        }
        context.restoreGState()
    }

    /// Measures the painted glyph in unit coordinates, including its outline.
    static func visibleBounds(
        for kind: Kind
    ) -> CGRect {
        let glyph = path(kind)
        let painted = isFilled(kind) ? glyph : glyph.copy(
            strokingWithWidth: strokeWidth(for: kind),
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 10
        )
        let bounds = painted.boundingBoxOfPath
        return CGRect(x: bounds.minX / 24, y: bounds.minY / 24, width: bounds.width / 24, height: bounds.height / 24)
    }

    /// Identifies glyphs whose path is filled when drawn.
    private static func isFilled(
        _ kind: Kind
    ) -> Bool {
        kind == .lightning || kind == .socialX || kind == .wechat || kind == .stop
    }

    /// Shares outline widths between drawing and layout measurement.
    private static func strokeWidth(
        for kind: Kind
    ) -> CGFloat {
        switch kind {
        case .arrow, .close: 3
        case .plus, .microphone: 2
        default: 1.8
        }
    }

    /// Builds the selected glyph in its shared 24-point coordinate space.
    private static func path(
        _ kind: Kind
    ) -> CGPath {
        var p = CGMutablePath()
        func line(
            _ points: [CGPoint]
        ) {
            guard let first = points.first else { return }
            p.move(to: first)
            for point in points.dropFirst() { p.addLine(to: point) }
        }
        func points(
            _ values: [(CGFloat, CGFloat)]
        ) -> [CGPoint] {
            values.map {
                CGPoint(
                    x: $0.0,
                    y: $0.1
                )
            }
        }
        switch kind {
        case .display:
            p.addRoundedRect(
                in: CGRect(
                    x: 2,
                    y: 3,
                    width: 20,
                    height: 14
                ),
                cornerWidth: 1,
                cornerHeight: 1
            )
            line(points([(9, 17), (9, 21), (15, 21), (15, 17)]))
            line(points([(7, 21), (17, 21)]))
        case .stop:
            p.addRect(
                CGRect(
                    x: 5,
                    y: 5,
                    width: 14,
                    height: 14
                )
            )
        case .key:
            p.addEllipse(
                in: CGRect(
                    x: 2,
                    y: 10,
                    width: 11,
                    height: 11
                )
            )
            line(points([(11.39, 11.61), (21, 2)]))
            line(points([(15.5, 7.5), (18.5, 10.5), (22, 7), (19, 4)]))
        case .camera:
            p.addRoundedRect(
                in: CGRect(
                    x: 2,
                    y: 6,
                    width: 14,
                    height: 12
                ),
                cornerWidth: 3,
                cornerHeight: 3
            )
            line(points([(16, 10), (22, 6.5), (22, 17.5), (16, 14)]))
        case .microphone:
            p.addRoundedRect(
                in: CGRect(
                    x: 9,
                    y: 2,
                    width: 6,
                    height: 13
                ),
                cornerWidth: 3,
                cornerHeight: 3
            )
            p.move(
                to: CGPoint(
                    x: 19,
                    y: 10
                )
            )

            p.addLine(
                to: CGPoint(
                    x: 19,
                    y: 12
                )
            )
            p.addCurve(
                to: CGPoint(
                    x: 5,
                    y: 12
                ),
                control1: CGPoint(
                    x: 19,
                    y: 21.3
                ),
                control2: CGPoint(
                    x: 5,
                    y: 21.3
                )
            )
            p.addLine(
                to: CGPoint(
                    x: 5,
                    y: 10
                )
            )
            line(points([(12, 19), (12, 22)]))
        case .statistics:
            line(points([(4, 4), (4, 20), (20, 20)]))
            line(points([(8, 15), (8, 11)]))
            line(points([(13, 15), (13, 7)]))
            line(points([(18, 15), (18, 9)]))
        case .muted, .volume, .volumeLow:
            line(points([(11, 4), (6, 8), (3, 8), (3, 16), (6, 16), (11, 20), (11, 4)]))
            if kind == .muted {
                line(points([(16, 9), (22, 15)]))
                line(points([(22, 9), (16, 15)]))
            } else {
                p.move(
                    to: CGPoint(
                        x: 15,
                        y: 8
                    )
                )
                p.addCurve(
                    to: CGPoint(
                        x: 15,
                        y: 16
                    ),
                    control1: CGPoint(
                        x: 18,
                        y: 10
                    ),
                    control2: CGPoint(
                        x: 18,
                        y: 14
                    )
                )
                if kind == .volume {
                    p.move(
                        to: CGPoint(
                            x: 18,
                            y: 5
                        )
                    )
                    p.addCurve(
                        to: CGPoint(
                            x: 18,
                            y: 19
                        ),
                        control1: CGPoint(
                            x: 24,
                            y: 9
                        ),
                        control2: CGPoint(
                            x: 24,
                            y: 15
                        )
                    )
                }
            }
        case .lightning:
            line(points([(13.7, 2.3), (4.2, 13), (10.4, 14.2), (9.5, 21.7), (19.8, 11), (12.9, 9.8), (13.7, 2.3)]))

            p.closeSubpath()
        case .plus:
            line(points([(12, 4), (12, 20)]))
            line(points([(4, 12), (20, 12)]))
        case .close:
            line(points([(5, 5), (19, 19)]))
            line(points([(19, 5), (5, 19)]))
        case .arrow:
            line(points([(4, 12), (20, 12)]))
            line(points([(14, 6), (20, 12), (14, 18)]))
        case .globe:
            p.addEllipse(
                in: CGRect(
                    x: 2,
                    y: 2,
                    width: 20,
                    height: 20
                )
            )
            line(points([(2, 12), (22, 12)]))
            p.move(
                to: CGPoint(
                    x: 12,
                    y: 2
                )
            )
            p.addCurve(
                to: CGPoint(
                    x: 12,
                    y: 22
                ),
                control1: CGPoint(
                    x: 17.3,
                    y: 7
                ),
                control2: CGPoint(
                    x: 17.3,
                    y: 17
                )
            )
            p.addCurve(
                to: CGPoint(
                    x: 12,
                    y: 2
                ),
                control1: CGPoint(
                    x: 6.7,
                    y: 17
                ),
                control2: CGPoint(
                    x: 6.7,
                    y: 7
                )
            )
        case .socialX:
            line(
                points([
                    (18.244, 2.25), (21.552, 2.25), (14.325, 10.51), (22.827, 21.75), (16.17, 21.75), (10.956, 14.933),
                    (4.99, 21.75), (1.68, 21.75), (9.41, 12.915), (1.254, 2.25), (8.08, 2.25), (12.793, 8.481),
                    (18.244, 2.25),
                ])
            )
            p.closeSubpath()
            line(points([(17.083, 19.77), (18.916, 19.77), (6.95, 4.126), (5.117, 4.126), (17.083, 19.77)]))

            p.closeSubpath()
        case .wechat:
            p.move(
                to: CGPoint(
                    x: 9.3,
                    y: 4
                )
            )
            p.addCurve(
                to: CGPoint(
                    x: 2.6,
                    y: 9.9
                ),
                control1: CGPoint(
                    x: 5.6,
                    y: 4
                ),
                control2: CGPoint(
                    x: 2.6,
                    y: 6.6
                )
            )
            p.addCurve(
                to: CGPoint(
                    x: 5.2,
                    y: 14.5
                ),
                control1: CGPoint(
                    x: 2.6,
                    y: 11.8
                ),
                control2: CGPoint(
                    x: 3.6,
                    y: 13.4
                )
            )
            p.addLine(
                to: CGPoint(
                    x: 4.5,
                    y: 16.7
                )
            )

            p.addLine(
                to: CGPoint(
                    x: 6.9,
                    y: 15.5
                )
            )
            p.addCurve(
                to: CGPoint(
                    x: 9.3,
                    y: 15.8
                ),
                control1: CGPoint(
                    x: 7.6,
                    y: 15.7
                ),
                control2: CGPoint(
                    x: 8.4,
                    y: 15.8
                )
            )
            p.addLine(
                to: CGPoint(
                    x: 9.8,
                    y: 15.8
                )
            )
            p.addCurve(
                to: CGPoint(
                    x: 9.6,
                    y: 14.5
                ),
                control1: CGPoint(
                    x: 9.7,
                    y: 15.4
                ),
                control2: CGPoint(
                    x: 9.6,
                    y: 14.9
                )
            )
            p.addCurve(
                to: CGPoint(
                    x: 16,
                    y: 8.9
                ),
                control1: CGPoint(
                    x: 9.6,
                    y: 11.4
                ),
                control2: CGPoint(
                    x: 12.5,
                    y: 8.9
                )
            )
            p.addLine(
                to: CGPoint(
                    x: 16.3,
                    y: 8.9
                )
            )
            p.addCurve(
                to: CGPoint(
                    x: 9.3,
                    y: 4
                ),
                control1: CGPoint(
                    x: 15.7,
                    y: 6.2
                ),
                control2: CGPoint(
                    x: 12.8,
                    y: 4
                )
            )
            p.closeSubpath()
            p.addEllipse(
                in: CGRect(
                    x: 6.4,
                    y: 7.2,
                    width: 1.8,
                    height: 1.8
                )
            )
            p.addEllipse(
                in: CGRect(
                    x: 10.8,
                    y: 7.2,
                    width: 1.8,
                    height: 1.8
                )
            )
            p.move(
                to: CGPoint(
                    x: 15.8,
                    y: 9.9
                )
            )
            p.addCurve(
                to: CGPoint(
                    x: 10.2,
                    y: 14.5
                ),
                control1: CGPoint(
                    x: 12.7,
                    y: 9.9
                ),
                control2: CGPoint(
                    x: 10.2,
                    y: 11.9
                )
            )
            p.addCurve(
                to: CGPoint(
                    x: 15.8,
                    y: 19.1
                ),
                control1: CGPoint(
                    x: 10.2,
                    y: 17
                ),
                control2: CGPoint(
                    x: 12.7,
                    y: 19.1
                )
            )
            p.addCurve(
                to: CGPoint(
                    x: 17.7,
                    y: 18.8
                ),
                control1: CGPoint(
                    x: 16.4,
                    y: 19.1
                ),
                control2: CGPoint(
                    x: 17.1,
                    y: 19
                )
            )
            p.addLine(
                to: CGPoint(
                    x: 19.7,
                    y: 19.8
                )
            )

            p.addLine(
                to: CGPoint(
                    x: 19.2,
                    y: 18
                )
            )
            p.addCurve(
                to: CGPoint(
                    x: 21.4,
                    y: 14.5
                ),
                control1: CGPoint(
                    x: 20.5,
                    y: 17.2
                ),
                control2: CGPoint(
                    x: 21.4,
                    y: 15.9
                )
            )
            p.addCurve(
                to: CGPoint(
                    x: 15.8,
                    y: 9.9
                ),
                control1: CGPoint(
                    x: 21.4,
                    y: 12
                ),
                control2: CGPoint(
                    x: 18.9,
                    y: 9.9
                )
            )
            p.closeSubpath()
            p.addEllipse(
                in: CGRect(
                    x: 13.4,
                    y: 12.4,
                    width: 1.6,
                    height: 1.6
                )
            )
            p.addEllipse(
                in: CGRect(
                    x: 16.6,
                    y: 12.4,
                    width: 1.6,
                    height: 1.6
                )
            )
            var transform = CGAffineTransform(
                a: 1.15,
                b: 0,
                c: 0,
                d: 1.15,
                tx: -1.8,
                ty: -1.8
            )
            p = p.mutableCopy(using: &transform) ?? p
        }
        return p
    }
}
