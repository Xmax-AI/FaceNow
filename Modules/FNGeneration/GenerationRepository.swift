//
//  GenerationRepository.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import Factory
import AVFoundation
import Combine
import CoreMedia
import CoreGraphics
import Foundation
import ImageIO
import XmaxSDK
import os

/// Owns generation state, reference uploads, preview bindings, and generated-frame delivery.
@MainActor
final class GenerationRepository: ObservableObject {

    /// The user settings supplying credentials when a session starts.
    @Injected(\.userRepo) private var userRepo: UserRepository

    /// The editable prompt used by Free Prompt generation.
    @Published var prompt = ""

    /// The camera application always uses X2.1.
    let model = RealtimeModel.x2_1

    /// Whether diagnostic panels are visible; collection remains independent.
    @Published var statisticsVisible = false

    /// The selected reference mode and owner of the current selection intent.
    @Published var activeMode = GenerationMode.charx {
        didSet {
            selectionIntent = UUID()
            errorMessage = nil
        }
    }

    /// Physical inputs exclude the virtual output to prevent feedback loops.
    @Published var cameraID = "" {
        didSet { virtualCameraRepo.updateInputSelection(cameraID) }
    }

    /// The currently selectable physical inputs, excluding FaceNow's own output.
    @Published private(set) var cameras: [CaptureDevice] = []

    /// The sentinel disabling microphone permission and capture for this session.
    static let disabledMicrophoneID = "disabled"

    /// The saved input UID; an empty or legacy selection is resolved during device discovery.
    @Published var microphoneID = UserDefaults.standard.string(forKey: "generation.microphone.id") ?? "" {
        didSet { UserDefaults.standard.set(microphoneID, forKey: "generation.microphone.id") }
    }

    /// The SDK input selection corresponding to the saved picker choice.
    private var selectedMicrophone: RealtimeMicrophone {
        microphoneID.isEmpty || microphoneID == Self.disabledMicrophoneID
            ? .disabled : .device(id: microphoneID)
    }

    /// The available audio inputs, excluding FaceNow's virtual microphone output.
    @Published private(set) var microphones: [CaptureDevice] = []

    /// Whether a runtime audio change owns the input selector until SDK configuration completes.
    @Published private(set) var microphoneSwitching = false

    /// Allows startup selection or a runtime microphone change while other generation work is idle.
    var canChangeMicrophone: Bool {
        !isBusy && !isClosing && !microphoneSwitching && !testPatternActive
            && (!sessionActive || [.ready, .connected, .generating].contains(state.connectionState))
    }

    /// Rejects stale input discovery results after another refresh or capture startup.
    private var microphoneRefreshID = UUID()

    /// Whether diagnostic video is using the virtual output without generation.
    @Published private(set) var testPatternActive = false

    // MARK: - State

    /// Whether local capture has opened the preview workspace, independently of cloud or virtual output.
    @Published private(set) var sessionActive = false

    /// The local camera stream retained through preview and asynchronous cleanup.
    @Published private(set) var localStream: RealtimeMediaStream?

    /// The generated result stream currently bound to the result preview.
    @Published private(set) var remoteStream: RealtimeMediaStream?

    /// The latest committed SDK connection and generation state.
    @Published private(set) var state = RealtimeState(connectionState: .idle)

    /// The failure presented by the home coordinator.
    @Published private(set) var errorMessage: String?

    /// Whether startup, configuration, or cleanup currently restricts user operations.
    @Published private(set) var isBusy = false

    /// Whether resource cleanup must complete before another session starts.
    @Published private(set) var isClosing = false

    /// The first generating transition's wall-clock time, used only for the elapsed-time label.
    @Published private(set) var sessionStartedAt: Date?

    /// The reference identity currently selected by the latest valid intent.
    @Published private(set) var selectedReferenceID: String?

    /// The user's reference images and their individual upload states.
    @Published private(set) var uploadedReferences: [GenerationReference] = []

    /// The SDK's startup-stage timing snapshot.
    @Published private(set) var launchTiming = RealtimeLaunchTiming()

    /// The app's Start-click-to-result-binding measurement.
    @Published private(set) var appLaunchTiming = AppLaunchTiming()

    /// The latest outgoing video statistics supplied by the SDK.
    @Published private(set) var uplinkStatistics: UplinkVideoStatistics?

    /// The latest incoming video statistics supplied by the SDK.
    @Published private(set) var downlinkStatistics: DownlinkVideoStatistics?

    /// The latest independent uplink and downlink quality levels.
    @Published private(set) var networkQuality: RealtimeNetworkQuality?

    /// The effective SDK interpolation state reflected by the toolbar.
    @Published private(set) var interpolationEnabled = true

    /// Whether an interpolation change is still being applied.
    @Published private(set) var interpolationSwitching = false

    /// The remote playback volume in the range zero through one.
    @Published private(set) var remoteAudioVolume: Float = 0

    /// The SDK's default result strengths, used when no user values have been saved.
    static let defaultBeautyOptions = RealtimeVideoBeautyOptions()

    /// The saved result beauty preference, disabled until explicitly enabled.
    @Published private(set) var beautyEnabled = false

    /// The editable strengths shared by result preview and virtual-camera output.
    @Published private(set) var beautyOptions = GenerationRepository.defaultBeautyOptions

    /// Whether the latest requested settings are being applied to the SDK.
    @Published private(set) var beautyApplying = false

    /// Coalesces continuous slider changes before submitting configuration.
    private var beautyDebounce: Task<Void, Never>?

    /// Serializes SDK updates while retaining only the latest desired settings.
    private var beautyApplication: Task<Void, Never>?

    /// Rejects superseded configuration results within the same session.
    private var beautyRevision: UInt64 = 0

    // MARK: - Dependencies

    /// The virtual-output owner consuming processed generated frames.
    @Injected(\.virtualCameraRepo) private var virtualCameraRepo: VirtualCameraRepository

    /// Sends the generated audio track to the opt-in system microphone.
    @Injected(\.virtualMicrophoneRepo) private var virtualMicrophoneRepo: VirtualMicrophoneRepository

    /// The transport owned by the shared virtual-camera repository.
    private var output: VirtualCameraOutput { virtualCameraRepo.output }

    /// The previous teardown task that a new startup must await.
    private var cleanup: Task<Void, Never>?

    /// The client retained while its media and storage services are in use.
    private var client: XmaxClient?

    /// The SDK generation manager for the current lifecycle.
    private var manager: (any XmaxRealtimeManaging)?

    /// The identity rejecting delayed state and frames from previous sessions.
    private var lifecycleID = UUID()

    /// The identity rejecting superseded prompt and reference selections.
    private var selectionIntent = UUID()

    /// The serialized reference-application task.
    private var application: Task<Void, Never>?

    /// The initial preset consumed once when local preview becomes ready.
    private var pendingInitialReference: GenerationReference?

    /// The virtual-output connection task cancelled before teardown.
    private var outputStartup: Task<Void, Never>?

    /// The shared physical and virtual device publication monitor.
    private var deviceMonitor: VirtualCameraDeviceMonitor { virtualCameraRepo.deviceMonitor }

    /// Reports startup milestones independently of per-frame media delivery.
    private let startupLogger = Logger(
        subsystem: VirtualCameraConfiguration.appBundleID,
        category: "Startup"
    )

    /// Retains device-change notifications without owning capture devices.
    private var deviceObservation: AnyCancellable?

    /// Presents nonfatal audio-output errors without ending the generation lifecycle.
    private var microphoneFailureObservation: AnyCancellable?

    /// Creates the SDK manager, allowing dependency-controlled construction.
    private let makeManager: (XmaxClient, RealtimeConfiguration) -> any XmaxRealtimeManaging

    /// Uploads prepared reference pixels through the current client's storage service.
    private let uploadImage: (XmaxClient, Data, String, XmaxStorageProgressHandler?) async throws -> URL

    /// Creates the generation owner with shared credentials and injectable service factories.
    init(
        user: UserRepository? = nil,
        makeManager: @escaping (XmaxClient, RealtimeConfiguration) -> any XmaxRealtimeManaging = {
            $0.createRealtimeManager(options: $1)
        },
        uploadImage: @escaping (XmaxClient, Data, String, XmaxStorageProgressHandler?) async throws -> URL = {
            client,
            data,
            name,
            progress in
            let storage = try client.createStorageManager()
            return try await storage.uploadImage(
                data,
                fileName: name,
                contentType: "image/jpeg",
                progress: progress
            ).url
        }
    ) {
        self.makeManager = makeManager
        self.uploadImage = uploadImage
        if let user { self.userRepo = user }
        let defaults = UserDefaults.standard
        beautyEnabled = defaults.object(forKey: "generation.beauty.enabled") as? Bool ?? false
        let saved = defaults.dictionary(forKey: "generation.beauty.options") ?? [:]
        func strength(_ key: String, fallback: Float) -> Float {
            guard let value = saved[key] as? NSNumber, value.floatValue.isFinite else { return fallback }
            return min(1, max(0, value.floatValue))
        }
        beautyOptions = RealtimeVideoBeautyOptions(
            smoothness: strength("smoothness", fallback: Self.defaultBeautyOptions.smoothness),
            lightening: strength("lightening", fallback: Self.defaultBeautyOptions.lightening),
            sharpness: strength("sharpness", fallback: Self.defaultBeautyOptions.sharpness),
            redness: strength("redness", fallback: Self.defaultBeautyOptions.redness)
        )
        deviceObservation = deviceMonitor.changes.sink { [weak self] in self?.refreshCameras() }
        microphoneFailureObservation = virtualMicrophoneRepo.$failure.compactMap { $0 }.sink { [weak self] message in
            guard let self, self.sessionActive else { return }
            self.errorMessage = message
        }
        refreshCameras()
    }

    /// Whether the user component currently supplies a non-whitespace credential.
    var hasAPIKey: Bool { userRepo.hasAPIKey }

    /// Whether the current session accepts reference or prompt generation commands.
    var canGenerate: Bool { userRepo.hasVerifiedSession && hasAPIKey && !isBusy && !microphoneSwitching && sessionActive }

    /// The uploaded reference currently associated with Free Prompt.
    var freeReference: GenerationReference? { uploadedReferences.first { $0.mode == .free } }

    /// Whether the active mode contains an image that is still uploading.
    var referenceUploading: Bool {
        uploadedReferences.contains { $0.mode == activeMode && $0.uploadState == .uploading }
    }

    /// Publishes a setup failure without starting a capture session.
    func showSetupError(
        _ message: String
    ) { errorMessage = message }

    /// Setup changes are disabled while capture or virtual output is in use.
    var settingsLocked: Bool { isBusy || sessionActive || testPatternActive }

    /// Discovers physical inputs without opening a capture session.
    func refreshCameras() {
        guard !settingsLocked else { return }
        refreshMicrophones()
        let available = deviceMonitor.devices.filter {
            $0.uniqueID.caseInsensitiveCompare(VirtualCameraConfiguration.deviceID.uuidString) != .orderedSame
                && $0.localizedName != VirtualCameraConfiguration.deviceName
        }.map {
            CaptureDevice(
                id: $0.uniqueID,
                name: $0.localizedName
            )
        }
        if !cameras.elementsEqual(available, by: { $0.id == $1.id && $0.name == $1.name }) {
            cameras = available
        }
        // Preserve a valid explicit choice; otherwise select the first published physical input.
        let selection = available.contains(where: { $0.id == cameraID }) ? cameraID : available.first?.id ?? ""
        if selection != cameraID { cameraID = selection }
    }

    /// Refreshes inputs and resolves an initial selection to a concrete device without acquiring permission.
    @discardableResult
    func refreshMicrophones() -> Task<Void, Never>? {
        guard !isClosing else { return nil }
        let request = UUID()
        microphoneRefreshID = request
        return Task { [weak self] in
            let devices = await MediaDevices.listMicrophoneDevices()
            guard let self, self.microphoneRefreshID == request, !self.isClosing else { return }
            let inputs = devices.filter { $0.id != VirtualMicrophoneOutput.deviceUID }
            let available = inputs.map { CaptureDevice(id: $0.id, name: $0.name) }
            if !self.microphones.elementsEqual(available, by: { $0.id == $1.id && $0.name == $1.name }) {
                self.microphones = available
            }
            if self.microphoneID.isEmpty || self.microphoneID == "system-default" {
                self.microphoneID = inputs.first(where: \.isDefault)?.id
                    ?? inputs.first?.id ?? Self.disabledMicrophoneID
            }
        }
    }

    /// Applies a microphone choice and saves it only after the current SDK session accepts the change.
    func selectMicrophone(
        _ id: String
    ) async {
        guard canChangeMicrophone, id != microphoneID,
            id == Self.disabledMicrophoneID || microphones.contains(where: { $0.id == id })
        else { return }
        guard sessionActive, let manager else {
            microphoneID = id
            return
        }
        let operation = lifecycleID
        let previous = microphoneID
        microphoneSwitching = true
        defer { if lifecycleID == operation { microphoneSwitching = false } }
        var routeChanged = false
        do {
            if id == Self.disabledMicrophoneID {
                try await manager.setMicrophoneEnabled(false)
            } else {
                try await manager.switchMicrophone(to: id)
                routeChanged = true
                guard lifecycleID == operation, !isClosing else { return }
                try await manager.setMicrophoneEnabled(true)
            }
            guard lifecycleID == operation, !isClosing else { return }
            microphoneID = id
        } catch {
            guard lifecycleID == operation, !isClosing else { return }
            if routeChanged, previous != Self.disabledMicrophoneID {
                try? await manager.switchMicrophone(to: previous)
            }
            let enabled = await manager.isMicrophoneEnabled
            guard lifecycleID == operation, !isClosing else { return }
            if !enabled { microphoneID = Self.disabledMicrophoneID }
            errorMessage = error.localizedDescription
        }
    }

    /// Exercises the installed camera transport without starting a generation session.
    func toggleTestPattern() async {
        guard !isBusy, !sessionActive else { return }
        if testPatternActive {
            await close()
            return
        }
        isBusy = true
        errorMessage = nil
        let operation = lifecycleID
        await cleanup?.value
        guard lifecycleID == operation else { return }
        do {
            try await output.start(
                testPattern: true,
                generationCaption: GenerationStrings.controlsResult
            )
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

        /// The identity used to associate this value with its displayed or pending state.
        let id: String

        /// The user-visible name of the selected device or reference.
        let name: String
    }

    /// Creates and binds camera preview before starting generation when the SDK reports ready.
    func start(
        requestedAt: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) async {
        guard !isClosing else {
            errorMessage = GenerationStrings.errorThePreviousSessionIsStillStoppingPleaseTryAgain
            return
        }
        guard !isBusy, localStream == nil else { return }
        virtualCameraRepo.prepareCameraInputs()
        guard virtualCameraRepo.canStartSession else {
            errorMessage = virtualCameraRepo.startUnavailableMessage
            return
        }
        refreshCameras()
        guard !cameraID.isEmpty else {
            errorMessage = GenerationStrings.errorConnectAPhysicalCameraAndSelectItFromThe
            return
        }
        if testPatternActive { await close() }
        isBusy = true
        errorMessage = nil
        let operation = UUID()
        lifecycleID = operation
        appLaunchTiming.begin(
            operation: operation,
            at: requestedAt
        )
        startupLogger.notice("App startup accepted; measuring from Start click")
        await cleanup?.value
        guard lifecycleID == operation else { return }
        beautyEnabled = UserDefaults.standard.object(forKey: "generation.beauty.enabled") as? Bool ?? false
        advanceStartup(
            to: .appSetup,
            operation: operation
        )
        await refreshMicrophones()?.value
        guard lifecycleID == operation else { return }
        activeMode = .charx
        selectedReferenceID = nil
        launchTiming = RealtimeLaunchTiming()
        uplinkStatistics = nil
        downlinkStatistics = nil
        networkQuality = nil
        #if OVERSEA
            let environment = XmaxEnvironment.global
        #else
            let environment = XmaxEnvironment.china
        #endif
        let client = XmaxClient(
            configuration: XmaxConfiguration(
                apiKey: userRepo.apiKey,
                environment: environment,
                loggerOptions: .all
            )
        )
        let manager = makeManager(
            client,
            RealtimeConfiguration(
                model: model,
                isFrameInterpolationEnabled: interpolationEnabled
            )
        )
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
            if state.connectionState == .generating, self.sessionStartedAt == nil {
                self.sessionStartedAt = Date()
            }
            if ![.connected, .generating].contains(state.connectionState) { self.remoteStream = nil }
            if case let .failure(error) = state.reason {
                self.handleGenerationFailure(error, endsSession: true)
                return
            }
            if state.connectionState == .ready {
                Task { [weak self] in await self?.startPendingGeneration(operation: operation) }
            }
        }
        guard lifecycleID == operation else { return }
        guard let reference = GenerationMode.charx.presets.first else {
            resetSession()
            return
        }
        selectedReferenceID = reference.id
        do {
            output.frames.reset(producer: operation)
            let mailbox = output.frames
            let microphone = virtualMicrophoneRepo.output
            microphone.reset(producer: operation)
            try await manager.setRemoteMediaFrameListener { event in
                switch event.content {
                case .audio(let frame):
                    microphone.submit(
                        data: frame.data,
                        sourceRate: frame.sampleRate,
                        channels: frame.channels,
                        samplesPerChannel: frame.samplesPerChannel,
                        producer: operation,
                        discontinuous: event.isDiscontinuous,
                        presentationTime: mailbox.presentationTime(
                            forSourceTimestamp: frame.presentationTimeStamp.seconds,
                            producer: operation
                        )
                    )
                case .video(let frame):
                    mailbox.submit(
                        frame.pixelBuffer,
                        producer: operation,
                        timestamp: frame.presentationTimeStamp.seconds,
                        duration: frame.duration.seconds,
                        now: CMClockGetTime(CMClockGetHostTimeClock()).seconds
                    )
                }
            }
            guard lifecycleID == operation else { return }
            advanceStartup(
                to: .generation,
                operation: operation
            )
            let stream = try await manager.createLocalCameraStream(
                deviceID: cameraID,
                mirror: false,
                microphone: selectedMicrophone
            )
            guard lifecycleID == operation else {
                await manager.close()
                return
            }
            localStream = stream
            sessionActive = true
            await manager.setRemoteVideoBeautyErrorListener { [weak self] error in
                guard let self, self.lifecycleID == operation else { return }
                self.disableBeautyAfterFailure(error)
            }
            guard lifecycleID == operation else { return }
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "generation.beauty.enabled") != nil
                || defaults.object(forKey: "generation.beauty.options") != nil
            {
                await applyPendingBeauty()
            }
            guard lifecycleID == operation else { return }
            try await manager.setRemoteAudioVolume(remoteAudioVolume)
            guard lifecycleID == operation else { return }
            pendingInitialReference = reference
            await startPendingGeneration(operation: operation)
        } catch {
            guard lifecycleID == operation else { return }
            handleGenerationFailure(error, endsSession: true)
            await cleanup?.value
        }
    }

    /// Consumes the initial preset once, regardless of whether ready arrives before or after stream creation returns.
    private func startPendingGeneration(
        operation: UUID
    ) async {
        guard lifecycleID == operation, localStream != nil, let reference = pendingInitialReference else { return }
        guard userRepo.hasVerifiedSession, hasAPIKey else {
            pendingInitialReference = nil
            isBusy = false
            return
        }
        guard state.connectionState == .ready else { return }
        pendingInitialReference = nil
        do {
            try await generate(reference: reference)
            guard lifecycleID == operation else { return }
            isBusy = false
        } catch {
            guard lifecycleID == operation else { return }
            handleGenerationFailure(error)
            if lifecycleID == operation { isBusy = false }
        }
    }

    /// Connects optional virtual output after generation when the extension is ready.
    private func startVirtualOutput(
        operation: UUID
    ) {
        virtualCameraRepo.synchronizeReadiness()
        guard virtualCameraRepo.isVirtualCameraReady, outputStartup == nil else { return }
        outputStartup = Task { [weak self, output] in
            let startedAt = ContinuousClock.now
            do {
                try Task.checkCancellation()
                try await output.start(
                    testPattern: false,
                    generationCaption: GenerationStrings.controlsResult
                )
                try Task.checkCancellation()
                guard let self, self.lifecycleID == operation else { return }
                output.frames.reset(producer: operation)
                self.startupLogger.notice(
                    "Virtual camera output ready after result: \(startedAt.duration(to: .now).description, privacy: .public)"
                )
            } catch {
                guard !Task.isCancelled, let self, self.lifecycleID == operation else { return }
                let message = GenerationStrings.outputFailed(message: error.localizedDescription)
                self.startupLogger.error(
                    "Virtual camera output failed: \(error.localizedDescription, privacy: .public)"
                )
                self.outputStartup = nil
                self.errorMessage = message
            }
        }
    }

    /// Condition updates keep the page interactive; selections are applied serially with only the latest pending selection retained.
    func selectReference(
        _ reference: GenerationReference
    ) async {
        guard canGenerate, reference.uploadState != .uploading else { return }
        let intent = UUID()
        selectionIntent = intent
        if reference.uploadState == .error {
            await upload(
                reference: reference,
                intent: intent
            )
        } else {
            await enqueue(
                reference: reference,
                intent: intent
            )
        }
    }

    /// Free Prompt and image selection share the generation queue; switching tabs alone does not regenerate.
    func submitPrompt() async {
        guard canGenerate, !referenceUploading else { return }
        let reference = GenerationReference(
            id: freeReference?.id ?? UUID().uuidString,
            mode: .free,
            name: "",
            thumbnailURL: freeReference?.thumbnailURL,
            referencePath: freeReference?.referencePath ?? "",
            prompt: prompt
        )
        let intent = UUID()
        selectionIntent = intent
        await enqueue(
            reference: reference,
            intent: intent
        )
    }

    /// Local files appear first immediately; per-item progress and retries leave other controls available.
    func uploadReference(
        at fileURL: URL,
        mode: GenerationMode
    ) async {
        guard canGenerate else { return }
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let reference = GenerationReference(
                id: UUID().uuidString,
                mode: mode,
                name: fileURL.lastPathComponent,
                thumbnailURL: fileURL,
                referencePath: "",
                thumbnailData: data,
                prompt: mode == .free ? prompt : mode.prompt
            )
            uploadedReferences.insert(
                reference,
                at: 0
            )
            let intent = UUID()
            selectionIntent = intent
            await upload(
                reference: reference,
                intent: intent
            )
        } catch { errorMessage = error.localizedDescription }
    }

    /// Uploads one reference and applies it only if its selection intent remains current.
    private func upload(
        reference: GenerationReference,
        intent: UUID
    ) async {
        guard let client, let data = reference.thumbnailData else { return }
        let operation = lifecycleID
        patchReference(reference.id) {
            $0.uploadState = .uploading
            $0.uploadError = nil
            $0.uploadProgress = 0
        }
        errorMessage = nil
        do {
            let jpeg = try await Task.detached { try Self.jpegData(data) }.value
            let uploadedURL = try await uploadImage(
                client,
                jpeg,
                (reference.name as NSString).deletingPathExtension + ".jpg"
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
                await enqueue(
                    reference: ready,
                    intent: intent
                )
            }
        } catch {
            patchReference(reference.id) {
                $0.uploadState = .error
                $0.uploadError = error.localizedDescription
            }
            guard lifecycleID == operation else { return }
            if selectionIntent == intent { handleGenerationFailure(error) }
        }
    }

    /// Updates an existing reference by identity without replacing other items.
    private func patchReference(
        _ id: String,
        update: (inout GenerationReference) -> Void
    ) {
        guard let index = uploadedReferences.firstIndex(where: { $0.id == id }) else { return }
        update(&uploadedReferences[index])
    }

    /// Serializes generation updates and skips superseded selection intents.
    private func enqueue(
        reference: GenerationReference,
        intent: UUID
    ) async {
        let previous = application
        let operation = lifecycleID
        let task = Task { [weak self] in
            await previous?.value
            guard let self, self.lifecycleID == operation, self.selectionIntent == intent else { return }
            self.errorMessage = nil
            self.selectedReferenceID = reference.mode == .free && reference.referencePath.isEmpty ? nil : reference.id
            if reference.mode == .free { self.prompt = reference.prompt ?? self.prompt }
            do { try await self.generate(reference: reference) } catch {
                if self.lifecycleID == operation, self.selectionIntent == intent {
                    self.handleGenerationFailure(error)
                }
            }
        }
        application = task
        await task.value
    }

    /// Applies the selected reference and binds the resulting SDK stream.
    private func generate(
        reference: GenerationReference
    ) async throws {
        guard let manager, let localStream else { return }
        let operation = lifecycleID
        advanceStartup(
            to: .generation,
            operation: operation
        )
        let remote = try await manager.startGeneration(
            localStream: localStream,
            context: RealtimeContext(
                prompt: reference.prompt ?? reference.mode.prompt,
                referencePath: reference.referencePath.isEmpty ? nil : reference.referencePath
            ),
            faceRestoration: reference.mode.faceRestoration
        )
        guard lifecycleID == operation else { return }
        advanceStartup(
            to: .resultView,
            operation: operation
        )
        remoteStream = remote
        startVirtualOutput(operation: operation)
    }

    /// Called after the SDK's cached first result frame is bound to the visible result view.
    /// This is app readiness, not a GPU presentation or third-party virtual-camera receipt timestamp.
    func resultViewDidBecomeReady() {
        guard sessionActive, state.connectionState == .generating, remoteStream != nil,
            appLaunchTiming.totalMs == nil, appLaunchTiming.phase == .resultView
        else { return }
        guard
            appLaunchTiming.finish(
                operation: lifecycleID,
                at: DispatchTime.now().uptimeNanoseconds
            )
        else { return }
        let total = appLaunchTiming.totalMs ?? 0
        startupLogger.notice("App startup ready: total=\(total) ms; \(self.appLaunchTiming.summary, privacy: .public)")
    }

    /// Commits the next app startup phase only for the current lifecycle.
    private func advanceStartup(
        to phase: AppLaunchTiming.Phase,
        operation: UUID
    ) {
        // Avoid publishing timing changes for subsequent condition updates or stale completions.
        var timing = appLaunchTiming
        let previous = timing.phase
        guard
            timing.advance(
                to: phase,
                operation: operation,
                at: DispatchTime.now().uptimeNanoseconds
            )
        else { return }
        appLaunchTiming = timing
        if let previous, let duration = timing.milliseconds(for: previous) {
            startupLogger.notice("App startup phase: \(previous.name, privacy: .public)=\(duration) ms")
        }
    }

    /// Removes the Free Prompt image and invalidates pending selection work.
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

    /// Applies the opposite SDK interpolation setting while protecting the active lifecycle.
    func toggleInterpolation() async {
        guard sessionActive, !isBusy, !microphoneSwitching, let manager else { return }
        let operation = lifecycleID
        isBusy = true
        interpolationSwitching = true
        errorMessage = nil
        do { try await manager.setFrameInterpolationEnabled(!interpolationEnabled) } catch {
            if lifecycleID == operation { handleGenerationFailure(error) }
        }
        guard lifecycleID == operation else { return }
        await refreshInterpolationState()
        isBusy = false
        interpolationSwitching = false
    }

    /// Enables result beauty using the saved strengths, or restores original-frame output.
    func setBeautyEnabled(
        _ enabled: Bool
    ) {
        guard !isClosing, beautyEnabled != enabled else { return }
        beautyEnabled = enabled
        saveBeautyPreferences()
        scheduleBeautyApplication()
    }

    /// Stores slider values immediately and coalesces updates independently of generation commands.
    func setBeautyOptions(
        _ options: RealtimeVideoBeautyOptions
    ) {
        guard !isClosing, options != beautyOptions, (try? options.validate()) != nil else { return }
        beautyOptions = options
        saveBeautyPreferences()
        if beautyEnabled { scheduleBeautyApplication() }
    }

    /// Persists edition-local settings without saving any video or credentials.
    private func saveBeautyPreferences() {
        UserDefaults.standard.set(beautyEnabled, forKey: "generation.beauty.enabled")
        UserDefaults.standard.set(
            [
                "smoothness": beautyOptions.smoothness,
                "lightening": beautyOptions.lightening,
                "sharpness": beautyOptions.sharpness,
                "redness": beautyOptions.redness,
            ],
            forKey: "generation.beauty.options"
        )
    }

    /// Waits briefly for slider input to settle without interrupting an in-flight SDK operation.
    private func scheduleBeautyApplication() {
        beautyRevision &+= 1
        beautyDebounce?.cancel()
        guard sessionActive, !isClosing else { return }
        let operation = lifecycleID
        beautyDebounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            guard let self, self.lifecycleID == operation, !Task.isCancelled else { return }
            await self.applyPendingBeauty()
        }
    }

    /// Applies initial settings before generation and drains later changes using the latest values.
    private func applyPendingBeauty() async {
        if let beautyApplication {
            await beautyApplication.value
            return
        }
        guard let manager, sessionActive, !isClosing else { return }
        let operation = lifecycleID
        beautyApplying = true
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.lifecycleID == operation {
                    self.beautyApplying = false
                    self.beautyApplication = nil
                }
            }
            while self.lifecycleID == operation, !Task.isCancelled {
                let revision = self.beautyRevision
                let options = self.beautyEnabled ? self.beautyOptions : nil
                do {
                    try await manager.setRemoteVideoBeauty(options)
                } catch {
                    guard self.lifecycleID == operation, !Task.isCancelled else { return }
                    if revision == self.beautyRevision {
                        self.disableBeautyAfterFailure(error)
                    }
                }
                guard revision != self.beautyRevision else { return }
            }
        }
        beautyApplication = task
        await task.value
    }

    /// Reports a recoverable effect failure without overwriting the user's saved preference.
    private func disableBeautyAfterFailure(
        _ error: any Error
    ) {
        beautyEnabled = false
        beautyRevision &+= 1
        errorMessage = GenerationStrings.beautyUnavailable
        startupLogger.error("Result beauty disabled: \(error.localizedDescription, privacy: .public)")
    }

    /// Applies remote playback volume without letting a late operation overwrite a new session.
    func setRemoteAudioVolume(
        _ volume: Float
    ) async {
        guard let manager else { return }
        let operation = lifecycleID
        do {
            try await manager.setRemoteAudioVolume(volume)
            if lifecycleID == operation { remoteAudioVolume = volume }
        } catch { if lifecycleID == operation { handleGenerationFailure(error) } }
    }

    /// Returns terminal sessions to home while retaining their error through asynchronous cleanup.
    private func handleGenerationFailure(
        _ error: any Error,
        endsSession: Bool = false
    ) {
        let sdkError = error as? XmaxError
        let isPlatformFailure = sdkError?.code == .apiError || sdkError?.code == .sessionError
        let insufficientCredits =
            isPlatformFailure
            && GenerationFailure.isInsufficientCredits(
                apiCode: sdkError?.apiCode,
                message: error.localizedDescription
            )
        if endsSession || insufficientCredits { resetSession() }
        errorMessage = insufficientCredits ? AccountStrings.insufficientCredits : error.localizedDescription
    }

    /// Clears the currently displayed setup or generation failure.
    func dismissError() { errorMessage = nil }

    /// Returns to the landing page immediately and prevents a restart until media teardown finishes.
    func close() async {
        guard !isClosing, isBusy || sessionActive || testPatternActive || localStream != nil else { return }
        resetSession()
        errorMessage = nil
        await cleanup?.value
        await userRepo.refreshCredits(force: true)
    }

    /// Quit also cancels an in-flight startup and waits for the sink to close.
    func shutdown() async {
        if !isClosing { resetSession() }
        await cleanup?.value
    }

    /// Invalidates pending work and starts ordered cleanup while retaining preview resources until stopped.
    private func resetSession() {
        let previousCleanup = cleanup
        let closingManager = manager
        let closingClient = client
        let closingOutputStartup = outputStartup
        let closingBeautyApplication = beautyApplication
        beautyDebounce?.cancel()
        beautyDebounce = nil
        beautyApplication?.cancel()
        beautyApplication = nil
        beautyApplying = false
        beautyRevision &+= 1
        closingOutputStartup?.cancel()
        outputStartup = nil
        output.frames.reset(producer: nil)
        let microphone = virtualMicrophoneRepo.output
        microphone.reset(producer: nil)
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
        microphoneSwitching = false
        sessionStartedAt = nil
        // Keep hidden video bindings alive while the landing page animates and resources are released.
        cleanup = Task { [output] in
            await previousCleanup?.value
            // A blocked virtual-camera transport must not delay stopping physical capture.
            async let outputStop: Void = Self.stopOutput(
                output,
                startup: closingOutputStartup
            )
            async let microphoneStop: Void = microphone.stop()
            try? await closingManager?.setRemoteMediaFrameListener(nil)
            await closingManager?.setStateListener(nil)
            await closingManager?.close()
            await closingBeautyApplication?.value
            await outputStop
            await microphoneStop
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

    /// Waits for a cancelled output startup to finish before stopping its transport.
    nonisolated private static func stopOutput(
        _ output: VirtualCameraOutput,
        startup: Task<Void, Never>?
    ) async {
        await startup?.value
        await output.stop()
    }

    /// Preserves the original dimensions and uploads white-background JPEG at 0.9 quality to avoid black transparent areas.
    nonisolated private static func jpegData(
        _ data: Data
    ) throws -> Data {
        guard
            let source = CGImageSourceCreateWithData(
                data as CFData,
                nil
            ),
            let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                nil
            ) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                ] as CFDictionary
            ),
            let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else {
            throw NSError(
                domain: "XmaxCamera",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        GenerationStrings.errorUnableToDecodeReferenceImagePleaseChooseASupported
                ]
            )
        }
        context.setFillColor(
            CGColor(
                gray: 1,
                alpha: 1
            )
        )
        context.fill(
            CGRect(
                x: 0,
                y: 0,
                width: image.width,
                height: image.height
            )
        )
        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: 0,
                width: image.width,
                height: image.height
            )
        )
        let output = NSMutableData()
        guard let flattened = context.makeImage(),
            let destination = CGImageDestinationCreateWithData(
                output,
                "public.jpeg" as CFString,
                1,
                nil
            )
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(
            destination,
            flattened,
            [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return output as Data
    }
}

extension Container {

    /// The shared Generation repository registered for this container.
    @MainActor
    var generationRepo: Factory<GenerationRepository> {
        Factory(self) { @MainActor in GenerationRepository() }.singleton
    }
}
