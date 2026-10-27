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
import CoreMedia
import CoreGraphics
import Foundation
import ImageIO
import XmaxSDK
import os

/// Coordinates the example workflow, reference uploads, and generated-frame virtual output.
@MainActor
final class CameraSessionController: ObservableObject {

    /// User settings are persisted per user, matching the Web localStorage behavior.
    @Published var apiKey = UserDefaults.standard.string(forKey: "xmax.camera.apiKey") ?? "" {
        didSet { UserDefaults.standard.set(apiKey, forKey: "xmax.camera.apiKey") }
    }
    @Published var prompt = ""
    /// The camera application always uses the China preview model.
    let model = RealtimeModel.x2_1_1_preview_cn
    @Published var statisticsVisible = true
    @Published var activeMode = RealtimeExampleMode.charx {
        didSet {
            selectionIntent = UUID()
            errorMessage = nil
        }
    }

    /// Physical inputs exclude the virtual output to prevent feedback loops.
    @Published var cameraID = ""
    @Published private(set) var cameras: [CaptureDevice] = []
    @Published private(set) var testPatternActive = false

    /// Display state
    @Published private(set) var sessionActive = false
    @Published private(set) var localStream: RealtimeMediaStream?
    @Published private(set) var remoteStream: RealtimeMediaStream?
    @Published private(set) var state = RealtimeState(connectionState: .idle)
    @Published private(set) var errorMessage: String?
    @Published private(set) var isBusy = false
    @Published private(set) var isClosing = false
    @Published private(set) var sessionStartedAt: Date?
    @Published private(set) var selectedReferenceID: String?
    @Published private(set) var uploadedReferences: [RealtimeReference] = []
    @Published private(set) var launchTiming = RealtimeLaunchTiming()
    @Published private(set) var appLaunchTiming = AppLaunchTiming()
    @Published private(set) var uplinkStatistics: UplinkVideoStatistics?
    @Published private(set) var downlinkStatistics: DownlinkVideoStatistics?
    @Published private(set) var networkQuality: RealtimeNetworkQuality?
    @Published private(set) var interpolationEnabled = true
    @Published private(set) var interpolationSwitching = false
    @Published private(set) var remoteAudioVolume: Float = 0

    /// SDK resources and operation ownership
    private let output = VirtualCameraOutput()
    private var cleanup: Task<Void, Never>?
    private var client: XmaxClient?
    private var manager: (any XmaxRealtimeManaging)?
    private var lifecycleID = UUID()
    private var selectionIntent = UUID()
    private var application: Task<Void, Never>?
    private var pendingInitialReference: RealtimeReference?
    private var outputStartup: Task<Void, Never>?
    private let deviceMonitor = CameraDeviceMonitor.shared
    private let startupLogger = Logger(subsystem: CameraConfiguration.appBundleID, category: "Startup")
    private var deviceObservation: AnyCancellable?
    private let makeManager: (XmaxClient, RealtimeConfiguration) -> any XmaxRealtimeManaging
    private let uploadImage: (XmaxClient, Data, String, XmaxStorageProgressHandler?) async throws -> URL

    init(
        makeManager: @escaping (XmaxClient, RealtimeConfiguration) -> any XmaxRealtimeManaging = {
            $0.createRealtimeManager(options: $1)
        },
        uploadImage: @escaping (XmaxClient, Data, String, XmaxStorageProgressHandler?) async throws -> URL = {
            client, data, name, progress in
            let storage = try client.createStorageManager()
            return try await storage.uploadImage(data, fileName: name, contentType: "image/jpeg", progress: progress).url
        }
    ) {
        self.makeManager = makeManager
        self.uploadImage = uploadImage
        deviceObservation = deviceMonitor.changes.sink { [weak self] in self?.refreshCameras() }
        refreshCameras()
    }

    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canGenerate: Bool { hasAPIKey && !isBusy && sessionActive }
    var freeReference: RealtimeReference? { uploadedReferences.first { $0.mode == .free } }
    var referenceUploading: Bool {
        uploadedReferences.contains { $0.mode == activeMode && $0.uploadState == .uploading }
    }

    func showSetupError(_ message: String) { errorMessage = message }

    /// Setup changes are disabled while capture or virtual output is in use.
    var settingsLocked: Bool { isBusy || sessionActive || testPatternActive }

    /// Discovers physical inputs without opening a capture session.
    func refreshCameras() {
        guard !settingsLocked else { return }
        cameras = deviceMonitor.devices.filter {
            $0.uniqueID.caseInsensitiveCompare(CameraConfiguration.deviceID.uuidString) != .orderedSame &&
            $0.localizedName != CameraConfiguration.deviceName
        }.map { CaptureDevice(id: $0.uniqueID, name: $0.localizedName) }
        if !cameras.contains(where: { $0.id == cameraID }) { cameraID = cameras.first?.id ?? "" }
    }

    /// Exercises the installed camera transport without starting a generation session.
    func toggleTestPattern() async {
        guard !isBusy, !sessionActive else { return }
        if testPatternActive { await close(); return }
        isBusy = true
        errorMessage = nil
        let operation = lifecycleID
        await cleanup?.value
        guard lifecycleID == operation else { return }
        do {
            try await output.start(testPattern: true)
            guard lifecycleID == operation else { return }
            testPatternActive = true
            isBusy = false
        } catch {
            guard lifecycleID == operation else { return }
            errorMessage = error.localizedDescription
            resetSession()
        }
    }

    /// A capture choice does not retain an AVFoundation device.
    struct CaptureDevice: Identifiable {
        let id: String
        let name: String
    }

    /// Creates and binds camera preview before starting generation when the SDK reports ready.
    func start(useMicrophone: Bool = false, requestedAt: UInt64 = DispatchTime.now().uptimeNanoseconds) async {
        guard !isClosing else {
            errorMessage = "The previous session is still stopping. Please try again in a moment."
            return
        }
        guard !isBusy, localStream == nil else { return }
        guard hasAPIKey else {
            errorMessage = "API Key is required — click the key button in the top-right corner to enter it"
            return
        }
        guard deviceMonitor.isStarted else {
            errorMessage = "Enable Virtual Camera before starting the camera."
            return
        }
        guard !cameraID.isEmpty else {
            errorMessage = "Connect a physical camera and select it from the camera list."
            return
        }
        if testPatternActive { await close() }
        isBusy = true
        errorMessage = nil
        let operation = UUID()
        lifecycleID = operation
        appLaunchTiming.begin(operation: operation, at: requestedAt)
        startupLogger.notice("App startup accepted; measuring from Start click")
        await cleanup?.value
        guard lifecycleID == operation else { return }
        advanceStartup(to: .appSetup, operation: operation)
        activeMode = .charx
        selectedReferenceID = nil
        launchTiming = RealtimeLaunchTiming()
        uplinkStatistics = nil
        downlinkStatistics = nil
        networkQuality = nil
        let client = XmaxClient(configuration: XmaxConfiguration(
            apiKey: apiKey,
            environment: .china,
            loggerOptions: .all
        ))
        let manager = makeManager(client, RealtimeConfiguration(
            model: model, isFrameInterpolationEnabled: interpolationEnabled
        ))
        self.client = client
        self.manager = manager
        await manager.setLaunchTimingListener { [weak self] timing in
            guard let self, self.lifecycleID == operation else { return }
            self.launchTiming = timing
        }
        await manager.setUplinkVideoStatisticsListener { [weak self] statistics in
            guard let self, self.lifecycleID == operation else { return }
            self.uplinkStatistics = statistics
        }
        await manager.setDownlinkVideoStatisticsListener { [weak self] statistics in
            guard let self, self.lifecycleID == operation else { return }
            self.downlinkStatistics = statistics
        }
        await manager.setNetworkQualityListener { [weak self] quality in
            guard let self, self.lifecycleID == operation else { return }
            self.networkQuality = quality
        }
        await manager.setStateListener { [weak self] state in
            guard let self, self.lifecycleID == operation else { return }
            self.state = state
            if [.connected, .generating].contains(state.connectionState), !self.sessionActive {
                self.sessionActive = true
                self.sessionStartedAt = Date()
            }
            if ![.connected, .generating].contains(state.connectionState) { self.remoteStream = nil }
            if case let .failure(error) = state.reason {
                self.errorMessage = error.message
                if !self.sessionActive {
                    self.resetSession()
                }
            }
            if state.connectionState == .ready {
                Task { [weak self] in await self?.startPendingGeneration(operation: operation) }
            }
        }
        guard lifecycleID == operation else { return }
        guard let reference = RealtimeExampleMode.charx.presets.first else {
            resetSession()
            return
        }
        selectedReferenceID = reference.id
        do {
            output.frames.reset(producer: operation)
            let mailbox = output.frames
            try await manager.setRemoteMediaFrameListener { event in
                guard case .video(let frame) = event.content else { return }
                mailbox.submit(frame.pixelBuffer, producer: operation, timestamp: frame.presentationTimeStamp.seconds,
                               duration: frame.duration.seconds,
                               now: CMClockGetTime(CMClockGetHostTimeClock()).seconds)
            }
            guard lifecycleID == operation else { return }
            advanceStartup(to: .generation, operation: operation)
            let stream = try await manager.createLocalCameraStream(
                deviceID: cameraID,
                mirror: false,
                useMicrophone: useMicrophone
            )
            guard lifecycleID == operation else { await manager.close(); return }
            // Keep the preview bound on the landing page so native capture can enter ready.
            localStream = stream
            try await manager.setRemoteAudioVolume(remoteAudioVolume)
            guard lifecycleID == operation else { return }
            pendingInitialReference = reference
            await startPendingGeneration(operation: operation)
        } catch {
            guard lifecycleID == operation else { return }
            errorMessage = error.localizedDescription
            resetSession()
            await cleanup?.value
        }
    }

    /// Consumes the initial preset once, regardless of whether ready arrives before or after stream creation returns.
    private func startPendingGeneration(operation: UUID) async {
        guard lifecycleID == operation, state.connectionState == .ready, localStream != nil,
              let reference = pendingInitialReference else { return }
        pendingInitialReference = nil
        do {
            try await generate(reference: reference)
            guard lifecycleID == operation else { return }
            isBusy = false
            startVirtualOutput(operation: operation)
        } catch {
            guard lifecycleID == operation else { return }
            errorMessage = error.localizedDescription
            resetSession()
            await cleanup?.value
        }
    }

    /// Virtual-camera discovery and connection start after the result is available, outside SDK startup.
    private func startVirtualOutput(operation: UUID) {
        outputStartup = Task { [weak self, output] in
            let startedAt = ContinuousClock.now
            do {
                try Task.checkCancellation()
                try await output.start(testPattern: false)
                try Task.checkCancellation()
                guard let self, self.lifecycleID == operation else { return }
                output.frames.reset(producer: operation)
                self.startupLogger.notice("Virtual camera output ready after result: \(startedAt.duration(to: .now).description, privacy: .public)")
            } catch {
                guard !Task.isCancelled, let self, self.lifecycleID == operation else { return }
                let message = "Virtual camera output failed: \(error.localizedDescription)"
                self.startupLogger.error("Virtual camera output failed: \(error.localizedDescription, privacy: .public)")
                // Do not leave a paid generation session running without its required output.
                // Clear this task before cleanup so output shutdown cannot await its own caller.
                self.outputStartup = nil
                self.resetSession()
                self.errorMessage = message
                await self.cleanup?.value
            }
        }
    }

    /// Condition updates keep the page interactive; selections are applied serially with only the latest pending selection retained.
    func selectReference(_ reference: RealtimeReference) async {
        guard canGenerate, reference.uploadState != .uploading else { return }
        let intent = UUID()
        selectionIntent = intent
        if reference.uploadState == .error {
            await upload(reference: reference, intent: intent)
        } else {
            await enqueue(reference: reference, intent: intent)
        }
    }

    /// Free Prompt and image selection share the generation queue; switching tabs alone does not regenerate.
    func submitPrompt() async {
        guard canGenerate, !referenceUploading else { return }
        let reference = RealtimeReference(
            id: freeReference?.id ?? UUID().uuidString, mode: .free, name: "",
            thumbnailURL: freeReference?.thumbnailURL ?? URL(fileURLWithPath: "/"),
            referencePath: freeReference?.referencePath ?? "", prompt: prompt
        )
        let intent = UUID()
        selectionIntent = intent
        await enqueue(reference: reference, intent: intent)
    }

    /// Local files appear first immediately; per-item progress and retries leave other controls available.
    func uploadReference(at fileURL: URL, mode: RealtimeExampleMode) async {
        guard canGenerate else { return }
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let reference = RealtimeReference(
                id: UUID().uuidString, mode: mode, name: fileURL.lastPathComponent,
                thumbnailURL: fileURL, referencePath: "", thumbnailData: data,
                prompt: mode == .free ? prompt : mode.prompt
            )
            uploadedReferences.insert(reference, at: 0)
            let intent = UUID()
            selectionIntent = intent
            await upload(reference: reference, intent: intent)
        } catch { errorMessage = error.localizedDescription }
    }

    private func upload(reference: RealtimeReference, intent: UUID) async {
        guard let client, let data = reference.thumbnailData else { return }
        let operation = lifecycleID
        patchReference(reference.id) { $0.uploadState = .uploading; $0.uploadError = nil; $0.uploadProgress = 0 }
        errorMessage = nil
        do {
            let jpeg = try await Task.detached { try Self.jpegData(data) }.value
            let uploadedURL = try await uploadImage(
                client, jpeg, (reference.name as NSString).deletingPathExtension + ".jpg"
            ) { [weak self] progress in
                let fraction = progress.fractionCompleted
                Task { @MainActor in
                    guard let self else { return }
                    self.patchReference(reference.id) { $0.uploadProgress = fraction }
                }
            }
            patchReference(reference.id) {
                $0.referencePath = uploadedURL.absoluteString
                $0.uploadState = .ready
                $0.uploadProgress = 1
            }
            guard lifecycleID == operation else { return }
            if let ready = uploadedReferences.first(where: { $0.id == reference.id }) {
                await enqueue(reference: ready, intent: intent)
            }
        } catch {
            patchReference(reference.id) { $0.uploadState = .error; $0.uploadError = error.localizedDescription }
            guard lifecycleID == operation else { return }
            if selectionIntent == intent { errorMessage = error.localizedDescription }
        }
    }

    private func patchReference(_ id: String, update: (inout RealtimeReference) -> Void) {
        guard let index = uploadedReferences.firstIndex(where: { $0.id == id }) else { return }
        update(&uploadedReferences[index])
    }

    private func enqueue(reference: RealtimeReference, intent: UUID) async {
        let previous = application
        let operation = lifecycleID
        let task = Task { [weak self] in
            await previous?.value
            guard let self, self.lifecycleID == operation, self.selectionIntent == intent else { return }
            self.errorMessage = nil
            self.selectedReferenceID = reference.mode == .free && reference.referencePath.isEmpty ? nil : reference.id
            if reference.mode == .free { self.prompt = reference.prompt ?? self.prompt }
            do { try await self.generate(reference: reference) }
            catch {
                if self.lifecycleID == operation, self.selectionIntent == intent {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
        application = task
        await task.value
    }

    private func generate(reference: RealtimeReference) async throws {
        guard let manager, let localStream else { return }
        let operation = lifecycleID
        advanceStartup(to: .generation, operation: operation)
        let remote = try await manager.startGeneration(
            localStream: localStream,
            context: RealtimeContext(prompt: reference.prompt ?? reference.mode.prompt,
                                     referencePath: reference.referencePath.isEmpty ? nil : reference.referencePath),
            faceRestoration: reference.mode.faceRestoration
        )
        guard lifecycleID == operation else { return }
        advanceStartup(to: .resultView, operation: operation)
        remoteStream = remote
    }

    /// Called after the SDK's cached first result frame is bound to the visible result view.
    /// This is app readiness, not a GPU presentation or third-party virtual-camera receipt timestamp.
    func resultViewDidBecomeReady() {
        guard sessionActive, state.connectionState == .generating, remoteStream != nil,
              appLaunchTiming.totalMs == nil, appLaunchTiming.phase == .resultView else { return }
        guard appLaunchTiming.finish(operation: lifecycleID, at: DispatchTime.now().uptimeNanoseconds) else { return }
        let total = appLaunchTiming.totalMs ?? 0
        startupLogger.notice("App startup ready: total=\(total) ms; \(self.appLaunchTiming.summary, privacy: .public)")
    }

    private func advanceStartup(to phase: AppLaunchTiming.Phase, operation: UUID) {
        // Avoid publishing timing changes for subsequent condition updates or stale completions.
        var timing = appLaunchTiming
        let previous = timing.phase
        guard timing.advance(to: phase, operation: operation, at: DispatchTime.now().uptimeNanoseconds) else { return }
        appLaunchTiming = timing
        if let previous, let duration = timing.milliseconds(for: previous) {
            startupLogger.notice("App startup phase: \(previous.name, privacy: .public)=\(duration) ms")
        }
    }

    func removeFreeReference() {
        guard !isBusy, let reference = freeReference else { return }
        selectionIntent = UUID()
        if selectedReferenceID == reference.id { selectedReferenceID = nil }
        uploadedReferences.removeAll { $0.id == reference.id }
    }

    /// Synchronizes the SDK interpolation setting and fallback state without updating buttons for every frame.
    func refreshInterpolationState() async {
        let operation = lifecycleID
        guard let manager else { return }
        let enabled = await manager.isFrameInterpolationEnabled
        if lifecycleID == operation, interpolationEnabled != enabled { interpolationEnabled = enabled }
    }

    func toggleInterpolation() async {
        guard sessionActive, !isBusy, let manager else { return }
        let operation = lifecycleID
        isBusy = true
        interpolationSwitching = true
        errorMessage = nil
        do { try await manager.setFrameInterpolationEnabled(!interpolationEnabled) }
        catch { if lifecycleID == operation { errorMessage = error.localizedDescription } }
        guard lifecycleID == operation else { return }
        await refreshInterpolationState()
        isBusy = false
        interpolationSwitching = false
    }

    func setRemoteAudioVolume(_ volume: Float) async {
        guard let manager else { return }
        let operation = lifecycleID
        do {
            try await manager.setRemoteAudioVolume(volume)
            if lifecycleID == operation { remoteAudioVolume = volume }
        } catch { if lifecycleID == operation { errorMessage = error.localizedDescription } }
    }

    func dismissError() { errorMessage = nil }

    /// Returns to the landing page immediately and prevents a restart until media teardown finishes.
    func close() async {
        guard !isClosing, isBusy || sessionActive || testPatternActive || localStream != nil else { return }
        resetSession()
        errorMessage = nil
        await cleanup?.value
    }

    /// Quit also cancels an in-flight startup and waits for the sink to close.
    func shutdown() async {
        if !isClosing { resetSession() }
        await cleanup?.value
    }

    private func resetSession() {
        let previousCleanup = cleanup
        let closingManager = manager
        let closingClient = client
        let closingOutputStartup = outputStartup
        closingOutputStartup?.cancel()
        outputStartup = nil
        output.frames.reset(producer: nil)
        application?.cancel()
        testPatternActive = false
        lifecycleID = UUID()
        appLaunchTiming = AppLaunchTiming()
        let operation = lifecycleID
        selectionIntent = UUID()
        pendingInitialReference = nil
        application = nil
        manager = nil
        client = nil
        sessionActive = false
        isBusy = true
        isClosing = true
        interpolationSwitching = false
        sessionStartedAt = nil
        // Keep hidden video bindings alive while the landing page animates and resources are released.
        cleanup = Task { [output] in
            await previousCleanup?.value
            // A blocked virtual-camera transport must not delay stopping physical capture.
            async let outputStop: Void = Self.stopOutput(output, startup: closingOutputStartup)
            try? await closingManager?.setRemoteMediaFrameListener(nil)
            await closingManager?.setStateListener(nil)
            await closingManager?.close()
            await outputStop
            withExtendedLifetime(closingClient) {}
            guard self.lifecycleID == operation else { return }
            self.localStream = nil
            self.remoteStream = nil
            self.state = RealtimeState(connectionState: .idle)
            self.selectedReferenceID = nil
            self.launchTiming = RealtimeLaunchTiming()
            self.uplinkStatistics = nil
            self.downlinkStatistics = nil
            self.networkQuality = nil
            self.isBusy = false
            self.isClosing = false
        }
    }

    nonisolated private static func stopOutput(_ output: VirtualCameraOutput, startup: Task<Void, Never>?) async {
        await startup?.value
        await output.stop()
    }

    /// Preserves the original dimensions and uploads white-background JPEG at 0.9 quality to avoid black transparent areas.
    nonisolated private static func jpegData(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: max(width, height)
              ] as CFDictionary),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw NSError(domain: "XmaxCamera", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Unable to decode reference image; please choose a supported image file"])
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let output = NSMutableData()
        guard let flattened = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, flattened, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return output as Data
    }
}
