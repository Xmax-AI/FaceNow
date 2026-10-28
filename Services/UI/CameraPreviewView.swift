//
//  CameraPreviewView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import AVFoundation

/// Displays a capture session without owning or starting its camera.
@MainActor
final class CameraPreviewView: NSView {

    /// The video layer that follows the view's constrained bounds.
    private let previewLayer = AVCaptureVideoPreviewLayer()

    /// Creates the video surface with a crop that fills its containing canvas.
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    /// Storyboard decoding is unsupported for this programmatic view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Binds the repository-owned session before capture begins.
    func bind(
        session: AVCaptureSession
    ) {
        guard previewLayer.session !== session else { return }
        previewLayer.session = session
    }

    /// Synchronizes only layer geometry; SnapKit owns the view's geometry.
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }
}
