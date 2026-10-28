//
//  HomeRepository.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Factory
import Combine
import Foundation
import AVFoundation

/// Supplies product destinations and owns the home page's independent local camera preview.
@MainActor
final class HomeRepository: ObservableObject {

    /// The video-only capture resource, separate from generation and virtual output.
    let cameraPreview = CameraPreviewSession()

    /// Whether the canvas should display live video and its dimming overlay.
    @Published private(set) var isPreviewing = false

    /// Prevents overlapping preview transitions while permission or capture work is pending.
    @Published private(set) var isPreviewLoading = false

    /// The selected input at the time of the preview request; nil means no pending or active preview.
    private(set) var previewDeviceID: String?

    /// Invalidates late authorization and startup completions when the page leaves preview.
    private var previewRequestID: UUID?

    /// Coalesces cleanup so generation waits for physical camera release even during another stop.
    private var previewStopTask: Task<Void, Never>?

    /// Requests video access only after an explicit preview click, then starts local capture.
    func startPreview(
        deviceID: String
    ) async throws {
        guard previewRequestID == nil, previewStopTask == nil else { return }
        let requestID = UUID()
        previewRequestID = requestID
        previewDeviceID = deviceID
        isPreviewLoading = true
        do {
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            guard previewRequestID == requestID else { throw CancellationError() }
            try await cameraPreview.start(
                deviceID: deviceID,
                excludedDeviceID: VirtualCameraConfiguration.deviceID.uuidString,
                excludedDeviceName: VirtualCameraConfiguration.deviceName
            )
            guard previewRequestID == requestID else { throw CancellationError() }
            isPreviewing = true
            isPreviewLoading = false
        } catch {
            guard previewRequestID == requestID else { throw CancellationError() }
            await stopPreview()
            throw error
        }
    }

    /// Invalidates pending permission results and awaits capture release before another owner starts.
    func stopPreview() async {
        if let previewStopTask {
            await previewStopTask.value
            return
        }
        guard previewRequestID != nil else { return }
        previewRequestID = nil
        previewDeviceID = nil
        isPreviewing = false
        isPreviewLoading = true
        let task = Task { await cameraPreview.stop() }
        previewStopTask = task
        await task.value
        previewStopTask = nil
        isPreviewLoading = false
    }

    /// The organization's public social profile.
    let socialURL = URL(string: "https://x.com/XmaxAIOfficial")!

    /// The public product website.
    let websiteURL = URL(string: "https://xmaxsi.com")!

    /// The product support destination.
    let contactURL = URL(string: "mailto:contact@xmax.ai")!

    /// The domestic API-key management portal.
    let platformURL = URL(string: "https://platform.xmaxai.com")!

    /// The follow-popover artwork loaded on demand by the view.
    let wechatImageURL = URL(string: "https://assets.22duck.fun/image/wechatAccount.jpg")!
}

extension Container {

    /// The shared Home repository registered for this container.
    @MainActor
    var homeRepo: Factory<HomeRepository> {
        Factory(self) { @MainActor in HomeRepository() }.singleton
    }
}
