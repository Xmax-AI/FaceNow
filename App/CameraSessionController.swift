//
//  CameraSessionController.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import AVFoundation
import Combine
import Foundation
import XmaxSDK

/// Coordinates SDK capture, generation and virtual output without changing SDK ownership.
@MainActor
final class CameraSessionController: ObservableObject {
    /// The editable generation settings, frozen while a session is active.
    @Published var apiKey = UserDefaults.standard.string(forKey: "xmax.camera.apiKey") ?? "" {
        didSet { UserDefaults.standard.set(apiKey, forKey: "xmax.camera.apiKey") }
    }
    @Published var prompt = "A cinematic portrait, natural lighting, detailed face"
    @Published var model: RealtimeModel = .x2_1_1_preview_cn
    @Published var cameraID = ""

    /// Physical inputs exclude this application's virtual output to prevent feedback loops.
    @Published private(set) var cameras: [CaptureDevice] = []

    /// The visible workflow state and current failure, if any.
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var status = "Ready to connect"
    @Published private(set) var errorMessage: String?

    /// The local preview must remain mounted for the SDK to become ready.
    @Published private(set) var localStream: RealtimeMediaStream?
    @Published private(set) var remoteStream: RealtimeMediaStream?

    /// The output worker is independent of both the SDK and the SwiftUI render loop.
    private let output = VirtualCameraOutput()

    /// Strong SDK ownership lasts until shutdown completes.
    private var client: XmaxClient?
    private var manager: (any XmaxRealtimeManaging)?

    /// Session tokens reject asynchronous callbacks from prior sessions.
    private var sessionID = UUID()
    private var preparationTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var shutdownTask: Task<Void, Never>?
    private var pendingPrompt: String?
    private var isLocalReady = false

    /// Discovers inputs without starting capture or requesting permission.
    init() { refreshCameras() }

    /// Whether setup fields may be edited.
    var isIdle: Bool { phase == .idle }

    /// Refreshes attached cameras, keeping a valid current selection.
    func refreshCameras() {
        guard isIdle else { return }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown], mediaType: .video, position: .unspecified
        )
        cameras = discovery.devices.filter {
            $0.uniqueID.caseInsensitiveCompare(CameraConfiguration.deviceID.uuidString) != .orderedSame &&
            $0.localizedName != CameraConfiguration.deviceName
        }.map { CaptureDevice(id: $0.uniqueID, name: $0.localizedName) }
        if !cameras.contains(where: { $0.id == cameraID }) { cameraID = cameras.first?.id ?? "" }
    }

    /// Starts the same sink with color bars, without accessing the camera or Xmax service.
    func startTestPattern() {
        guard isIdle else { return }
        errorMessage = nil
        phase = .preparing
        status = "Connecting virtual camera…"
        let token = UUID()
        sessionID = token
        preparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.output.start(testPattern: true)
                guard self.sessionID == token, !Task.isCancelled else { return }
                self.phase = .testing
                self.status = "Test pattern is live"
            } catch {
                guard self.sessionID == token else { return }
                self.stop(error: error.localizedDescription)
            }
        }
    }

    /// Opens the sink before capture, then waits for a bound preview before generating.
    func startGeneration() {
        guard isIdle else { return }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter an API key and prompt to start generation."
            return
        }
        guard !cameraID.isEmpty else {
            errorMessage = "Connect a physical camera and refresh the camera list."
            return
        }
        errorMessage = nil
        phase = .preparing
        status = "Connecting virtual camera…"
        let token = UUID()
        sessionID = token
        pendingPrompt = prompt
        let client = XmaxClient(configuration: XmaxConfiguration(
            apiKey: apiKey, environment: model == .x2_1_1_preview_us ? .global : .china, loggerOptions: .all
        ))
        let manager = client.createRealtimeManager(options: RealtimeConfiguration(model: model))
        self.client = client
        self.manager = manager
        let inputID = cameraID
        preparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.output.start(testPattern: false)
                guard self.sessionID == token, !Task.isCancelled else { return }
                self.output.frames.reset(producer: token)
                let mailbox = self.output.frames
                await manager.setRemoteVideoFrameListener { frame in
                    mailbox.submit(frame.pixelBuffer, producer: token,
                                   now: CMClockGetTime(CMClockGetHostTimeClock()).seconds)
                }
                await manager.setStateListener { [weak self] state in
                    guard let self, self.sessionID == token else { return }
                    if case let .failure(error) = state.reason {
                        self.stop(error: error.localizedDescription)
                        return
                    }
                    self.status = state.connectionState.rawValue
                    self.isLocalReady = state.connectionState == .ready
                    if self.isLocalReady { self.generateIfReady(token: token) }
                }
                guard self.sessionID == token, !Task.isCancelled else { return }
                self.status = "Starting camera…"
                let stream = try await manager.createLocalCameraStream(deviceID: inputID, useMicrophone: false)
                guard self.sessionID == token, !Task.isCancelled else { return }
                self.localStream = stream
                self.generateIfReady(token: token)
            } catch {
                guard self.sessionID == token else { return }
                self.stop(error: error.localizedDescription)
            }
        }
    }

    /// Stops publishing immediately and closes all capture and service resources.
    func stop(error: String? = nil) {
        guard phase != .idle, phase != .stopping else { return }
        sessionID = UUID()
        pendingPrompt = nil
        isLocalReady = false
        preparationTask?.cancel()
        generationTask?.cancel()
        output.frames.reset(producer: nil)
        phase = .stopping
        status = "Stopping…"
        if let error { errorMessage = error }
        let manager = manager
        shutdownTask = Task { [weak self] in
            guard let self else { return }
            await self.output.stop()
            await manager?.setRemoteVideoFrameListener(nil)
            await manager?.setStateListener(nil)
            await manager?.close()
            self.localStream = nil
            self.remoteStream = nil
            self.manager = nil
            self.client = nil
            self.preparationTask = nil
            self.generationTask = nil
            self.phase = .idle
            self.status = "Ready to connect"
        }
    }

    /// Finishes cleanup before macOS terminates the host app.
    func shutdown() async {
        stop()
        await shutdownTask?.value
    }

    /// Starts exactly once after the SDK confirms preview readiness.
    private func generateIfReady(token: UUID) {
        guard sessionID == token, generationTask == nil, isLocalReady,
              let manager, let stream = localStream, let prompt = pendingPrompt else { return }
        generationTask = Task { [weak self] in
            guard let self, self.sessionID == token, !Task.isCancelled else { return }
            self.pendingPrompt = nil
            self.status = "Starting generation…"
            do {
                let remote = try await manager.startGeneration(localStream: stream, context: RealtimeContext(prompt: prompt))
                guard self.sessionID == token, !Task.isCancelled else { return }
                self.remoteStream = remote
                self.phase = .generating
                self.status = "Generated video is live"
            } catch {
                guard self.sessionID == token else { return }
                self.stop(error: error.localizedDescription)
            }
        }
    }

    /// The host's visible lifecycle, including cancellable preparation.
    enum Phase { case idle, preparing, testing, generating, stopping }

    /// A lightweight capture-device choice without retaining AVFoundation objects.
    struct CaptureDevice: Identifiable {
        let id: String
        let name: String
    }
}
