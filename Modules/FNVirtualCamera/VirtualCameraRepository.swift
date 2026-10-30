//
//  VirtualCameraRepository.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Factory
import AppKit
import AVFoundation
import Combine
import SystemExtensions
import Darwin
import os

/// Owns shared camera preparation and explicit installation or removal of the virtual output.
@MainActor
final class VirtualCameraRepository: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {

    /// The sole generated-frame transport shared with generation.
    let output = VirtualCameraOutput()

    /// The shared device publisher used by generation and extension readiness.
    let deviceMonitor = VirtualCameraDeviceMonitor.shared

    /// The current system response displayed beside setup controls.
    @Published private(set) var status = CameraStrings.statusNotChecked

    /// Whether the system is processing a request or waiting for approval.
    @Published private(set) var isBusy = false

    /// User approval is a pending action rather than indeterminate processing.
    @Published private(set) var isAwaitingApproval = false

    /// Status queries are independent of a pending activation request.
    @Published private(set) var isRefreshing = false

    /// Whether an enabled matching extension was found by the system.
    @Published private(set) var isEnabled = false

    /// Whether the enabled extension matches the bundled build version.
    @Published private(set) var isVersionCurrent = false

    /// The single preparation result shared by home, onboarding, and generation.
    @Published private(set) var readiness: CameraReadiness = .checking(.permission)

    /// Retains one explicit workflow across extension callbacks and device-publication checks.
    @Published private(set) var operation: CameraOperationContext?

    /// Retains a failed explicit command independently of whether the old device is still usable.
    @Published private(set) var operationFailure: CameraOperationFailure?

    /// A durable user intent, independent from actual installed-extension and device facts.
    @Published private var setupWorkflow: CameraSetupWorkflow? {
        didSet {
            if oldValue != setupWorkflow { CameraSetupWorkflow.save(setupWorkflow, to: .standard) }
        }
    }

    /// Distinguishes a real system restart from closing and reopening the application.
    private let bootID = VirtualCameraRepository.currentBootID()

    /// Surfaces a failed query when setup is blocked while keeping a healthy camera silent.
    var preparationFailure: CameraOperationFailure? {
        operationFailure ?? (extensionSnapshot.availability.isReady ? nil : queryFailure)
    }

    /// A user-copyable diagnostic containing only camera setup and platform details.
    var setupDiagnostic: String {
        let failure = operationFailure ?? requestFailure ?? queryFailure
        return [
            "FaceNow camera setup",
            "App build: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")",
            "Extension build: \(bundledExtensionVersion ?? "unknown")",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Phase: \(setupWorkflow?.phase.rawValue ?? "none")",
            "Boot identity available: \(!bootID.isEmpty)",
            "Operation: \(failure?.operation.rawValue ?? "none")",
            "Error: \(failure?.errorDomain ?? "none") (\(failure?.errorCode.map(String.init) ?? "none"))",
            failure?.diagnosticMessage ?? status,
        ].joined(separator: "\n")
    }

    /// Reads the stable macOS boot-session identity without relying on wall-clock estimates.
    private static func currentBootID() -> String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Bounds indeterminate native progress while retaining the pending request identity for late callbacks.
    private var requestTimeoutTask: Task<Void, Never>?

    /// Remembers which device recovery steps the user has already attempted.
    private var deviceRecovery: CameraDeviceRecovery? {
        didSet {
            let key = "facenow.virtualCamera.recovery.v1"
            if let deviceRecovery, let data = try? JSONEncoder().encode(deviceRecovery) {
                UserDefaults.standard.set(data, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    /// Records recovery navigation without inferring that the user completed the system action.
    func recordRecoveryNavigation(
        relaunch: Bool
    ) {
        guard var recovery = deviceRecovery else { return }
        if relaunch {
            recovery.relaunchFromProcessID = ProcessInfo.processInfo.processIdentifier
        } else {
            recovery.settingsOpened = true
        }
        deviceRecovery = recovery
    }

    /// Associates property-query completion with the user workflow that requested it.
    private var propertiesOperationID: UUID?

    /// Associates a bounded device check with the workflow waiting for its result.
    private var readinessOperationID: UUID?

    /// Preserves the actual install or removal stage after a native request leaves its initiating method.
    private var pendingOperationKind = CameraOperation.install

    /// Marks replacement races without crossing actor isolation from a synchronous native callback.
    private nonisolated let replacementConflicts = OSAllocatedUnfairLock(initialState: Set<ObjectIdentifier>())

    /// Remains true after progress times out until macOS completes the original request.
    var hasPendingSystemRequest: Bool { pendingRequest != nil }

    /// Whether the user must finish removal in System Settings before setup may continue.
    var needsManualRemoval: Bool { setupWorkflow?.phase == .manualRemoval }

    /// Associates extension callbacks with the workflow that submitted the request.
    private var pendingOperationID: UUID?

    /// Rejects new work and late system results after application cleanup begins.
    private var isShuttingDown = false

    /// The latest system permission, refreshed without opening a capture session.
    @Published private(set) var cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)

    /// Whether an explicit system camera permission prompt is pending.
    @Published private(set) var isRequestingCameraAccess = false

    /// Whether camera permission permits local preview independently of virtual output.
    var canStartSession: Bool { readiness.isCameraAuthorized }

    /// Whether virtual output is usable independently of physical camera permission and selection.
    var isVirtualCameraReady: Bool { extensionSnapshot.availability.isReady }

    /// The permission explanation for an explicit local preview attempt.
    var startUnavailableMessage: String { readiness.message }

    /// Loads authorized physical inputs for home selection or preview without starting capture.
    func prepareCameraInputs() {
        synchronizeReadiness()
        guard canStartSession else { return }
        deviceMonitor.start()
        synchronizeReadiness()
    }

    /// Whether installation records have been received at least once.
    @Published private var hasCheckedInstallation = false

    /// Whether any extension record exists, including a disabled or removing copy.
    @Published private(set) var isInstalled = false

    /// The latest confirmed installation or discovery failure.
    @Published private var deviceFailure: CameraUnavailableReason?

    /// The most recent failed installation-properties query.
    @Published private var queryFailure: CameraOperationFailure?

    /// Keeps the failed extension command available for a typed retry after a properties refresh.
    private var requestFailure: CameraOperationFailure?

    /// The selected physical input supplied by the generation owner.
    @Published private var selectedInputID = ""

    /// Coalesces multi-property system callbacks into one committed readiness result.
    private var readinessUpdateScheduled = false

    /// Watches repository changes without exposing intermediate combinations to consumers.
    private var readinessObservation: AnyCancellable?

    /// Shares a pending camera permission request between explicit user actions.
    private var permissionTask: Task<Bool, Never>?

    /// Activation and device publication complete at different times.
    @Published private(set) var isWaitingForDevice = false

    /// Whether the published virtual device exposes a usable producer sink.
    @Published private(set) var isDeviceReady = false

    /// Keeps a deferred native completion distinct from a camera that is actually ready.
    @Published private(set) var isSystemCompletionPending = false

    /// The bounded device-publication and sink-discovery operation.
    private var readinessTask: Task<Void, Never>?

    /// Rejects delayed completion from superseded device-readiness checks.
    private var readinessID = UUID()

    /// Tracks which extension version has already received a bounded readiness check.
    private var readinessPolicy = VirtualCameraReadinessPolicy()

    /// Whether an explicit refresh should recheck a previously observed extension version.
    private var forceDeviceCheck = false

    /// Retains device-publication notifications without opening capture streams.
    private var deviceObservation: AnyCancellable?

    /// The optional host-versus-helper discovery comparison task.
    private var diagnosticTask: Task<Void, Never>?

    /// Rejects delayed results from cancelled discovery comparisons.
    private var diagnosticID = UUID()

    /// Whether an opt-in activation diagnostic is waiting for readiness evaluation.
    private var diagnoseAfterReadiness = false

    /// Defers host discovery while an explicit activation diagnostic is requested.
    private var deferDiscoveryUntilActivation = VirtualCameraDiagnostics.activationRequested

    /// Reports extension-state and discovery diagnostics without reading video frames.
    private let logger = Logger(
        subsystem: VirtualCameraConfiguration.appBundleID,
        category: "DiscoveryComparison"
    )

    /// Observes device publication while leaving extension activation to explicit user actions.
    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "facenow.virtualCamera.recovery.v1"),
            let recovery = try? JSONDecoder().decode(CameraDeviceRecovery.self, from: data),
            recovery.targetVersion == bundledExtensionVersion
        {
            deviceRecovery = recovery
        }
        setupWorkflow = CameraSetupWorkflow.load(from: .standard, targetVersion: bundledExtensionVersion ?? "")
        if let workflow = setupWorkflow {
            isSystemCompletionPending =
                workflow.phase == .waitingForRemovalRestart
                || workflow.phase == .waitingForInstallationRestart
            requestFailure = workflow.failure
            operationFailure = workflow.failure
        }
        synchronizeReadiness()
        readinessObservation = objectWillChange.sink { [weak self] in self?.scheduleReadinessUpdate() }
        deviceObservation = VirtualCameraDeviceMonitor.shared.changes.sink { [weak self] in
            guard let self else { return }
            self.synchronizeReadiness()
            guard !self.isBusy, !self.isSystemCompletionPending, !self.isWaitingForDevice else { return }
            if self.isDeviceReady, (try? VirtualCameraDiscovery.findSink()) != nil { return }
            // A late arrival must recover even after the previous bounded check timed out.
            if self.isEnabled, self.isVersionCurrent, self.pendingRequest == nil, !self.needsManualRemoval {
                self.cancelDeviceWait()
                self.waitForDevice()
            } else {
                self.refresh(
                    retryDeviceDiscovery: true,
                    preservingFailure: true
                )
            }
        }
    }

    /// Reads current permission and committed device facts without requesting access or opening capture.
    func synchronizeReadiness() {
        let authorization = AVCaptureDevice.authorizationStatus(for: .video)
        if authorization != cameraAuthorization { cameraAuthorization = authorization }
        let next = CameraReadiness.resolve(
            authorization: authorizationState,
            virtualCamera: extensionSnapshot.availability,
            inputCamera: inputAvailability
        )
        if next != readiness { readiness = next }
    }

    /// Projects one preparation stage from the same committed facts used by complete readiness.
    func readiness(
        for scope: CameraPreparationScope
    ) -> CameraReadiness {
        switch scope {
        case .complete:
            return readiness
        case .cameraInput:
            return CameraReadiness.resolve(
                authorization: authorizationState,
                virtualCamera: .ready,
                inputCamera: deviceMonitor.isStarted ? inputAvailability : .ready
            )
        case .virtualOutput:
            switch extensionSnapshot.availability {
            case .checking(let phase): return .checking(phase)
            case .unavailable(let reason): return .unavailable(reason)
            case .ready: return .ready
            }
        }
    }

    /// Records selection without taking ownership of a generation or preview session.
    func updateInputSelection(
        _ id: String
    ) {
        if selectedInputID != id { selectedInputID = id }
        synchronizeReadiness()
    }

    /// Starts or joins one explicit command; native request callbacks retain its operation identity.
    func perform(
        _ kind: CameraOperation
    ) async {
        synchronizeReadiness()
        guard canPerform(kind) else { return }
        let context = CameraOperationContext(kind: kind, origin: .user)
        operationFailure = nil
        requestFailure = nil
        requestFailureMessage = nil
        queryFailure = nil
        operation = context
        switch kind {
        case .requestAccess:
            await requestCameraAccess()
            finishOperation(context.id)
        case .discoverInput:
            deviceMonitor.start()
            await Task.yield()
            synchronizeReadiness()
            finishOperation(context.id)
        case .install, .reinstall:
            guard validateInstallationLocation() else {
                finishOperation(context.id)
                return
            }
            let requiresRemoval = kind == .reinstall
                || (isInstalled && !isVersionCurrent && !isSystemCompletionPending)
            isSystemCompletionPending = false
            deviceFailure = nil
            deviceRecovery = nil
            setupWorkflow = CameraSetupWorkflow(
                targetVersion: bundledExtensionVersion ?? "",
                phase: requiresRemoval ? .removing : .installing
            )
            if requiresRemoval {
                operation = CameraOperationContext(kind: .remove, origin: .user)
                deactivateExtension()
            } else {
                activateExtension()
            }
        case .remove:
            setupWorkflow = nil
            deactivateExtension()
        case .checkStatus, .discoverOutput:
            if kind == .discoverOutput, readinessTask != nil {
                readinessOperationID = context.id
            } else if propertiesRequest != nil {
                propertiesOperationID = context.id
                forceDeviceCheck = forceDeviceCheck || kind == .discoverOutput
            } else {
                refresh(retryDeviceDiscovery: kind == .discoverOutput)
            }
        }
    }

    /// Exposes native operation eligibility without duplicating request flags in a ViewModel.
    func canPerform(
        _ kind: CameraOperation
    ) -> Bool {
        guard !isShuttingDown, operation == nil else { return false }
        switch kind {
        case .requestAccess:
            return cameraAuthorization == .notDetermined
        case .discoverInput:
            return canStartSession
        case .checkStatus, .discoverOutput:
            return !isBusy
        case .install:
            return queryFailure == nil && pendingRequest == nil && hasCheckedInstallation
                && !isBusy && !isRefreshing && !isWaitingForDevice
        case .reinstall, .remove:
            return queryFailure == nil && pendingRequest == nil && hasCheckedInstallation && isInstalled
                && !isSystemCompletionPending
                && !isBusy && !isRefreshing && !isWaitingForDevice
        }
    }

    /// Completes only the workflow associated with the system result being committed.
    private func finishOperation(
        _ id: UUID?
    ) {
        guard let id, operation?.id == id else { return }
        operation = nil
        synchronizeReadiness()
    }

    /// Cancels view-independent pending work when the application is terminating.
    func cancelPendingOperations() {
        isShuttingDown = true
        propertiesRequest = nil
        pendingRequest = nil
        requestTimeoutTask?.cancel()
        requestTimeoutTask = nil
        propertiesOperationID = nil
        pendingOperationID = nil
        operation = nil
        permissionTask?.cancel()
        cancelDeviceWait()
        cancelDiscoveryComparison()
    }

    /// Requests camera access only after an explicit user action and shares the pending prompt.
    func requestCameraAccess() async {
        guard !isShuttingDown else { return }
        if let permissionTask {
            _ = await permissionTask.value
            synchronizeReadiness()
            return
        }
        synchronizeReadiness()
        guard cameraAuthorization == .notDetermined else { return }
        isRequestingCameraAccess = true
        synchronizeReadiness()
        let task = Task { await AVCaptureDevice.requestAccess(for: .video) }
        permissionTask = task
        _ = await task.value
        permissionTask = nil
        guard !isShuttingDown else { return }
        isRequestingCameraAccess = false
        synchronizeReadiness()
    }

    /// Projects platform authorization into the independent readiness model.
    private var authorizationState: CameraAuthorization {
        if isRequestingCameraAccess { return .requesting }
        switch cameraAuthorization {
        case .authorized: return .authorized
        case .notDetermined: return .notRequested
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .restricted
        }
    }

    /// Projects extension facts without coupling preparation to account or generation state.
    private var extensionSnapshot: VirtualCameraReadinessSnapshot {
        VirtualCameraReadinessSnapshot(
            hasChecked: hasCheckedInstallation,
            isInstalled: isInstalled,
            isEnabled: isEnabled,
            isVersionCurrent: isVersionCurrent,
            isRefreshing: isRefreshing,
            operation: isBusy ? (pendingKind == .deactivation ? .removal : .installation) : nil,
            isAwaitingApproval: isAwaitingApproval,
            isSystemCompletionPending: isSystemCompletionPending,
            isDeviceReady: isDeviceReady,
            isWaitingForDevice: isWaitingForDevice,
            failure: deviceFailure ?? requestFailure.map(CameraUnavailableReason.operationFailed),
            queryFailure: queryFailure
        )
    }

    /// Evaluates only a started discovery session, excluding the application's own virtual output.
    private var inputAvailability: CameraAvailability {
        guard deviceMonitor.isStarted else { return .checking(.inputDiscovery) }
        let inputs = deviceMonitor.devices.filter {
            $0.uniqueID.caseInsensitiveCompare(VirtualCameraConfiguration.deviceID.uuidString) != .orderedSame
                && $0.localizedName != VirtualCameraConfiguration.deviceName
        }
        guard !inputs.isEmpty else { return .unavailable(.noInputCamera) }
        if !selectedInputID.isEmpty, !inputs.contains(where: { $0.uniqueID == selectedInputID }) {
            return .unavailable(.selectedInputDisconnected)
        }
        return .ready
    }

    /// Waits until Combine's pre-assignment notifications have committed their related facts.
    private func scheduleReadinessUpdate() {
        guard !readinessUpdateScheduled else { return }
        readinessUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.readinessUpdateScheduled = false
            self.synchronizeReadiness()
        }
    }

    /// Identifies the in-flight request so delayed delegate calls cannot overwrite newer state.
    private var pendingRequest: OSSystemExtensionRequest?

    /// The activation or deactivation operation associated with the current request.
    private var pendingKind: RequestKind?

    /// The independent in-flight system extension properties query.
    private var propertiesRequest: OSSystemExtensionRequest?

    /// Background device/property refreshes must not erase the result of an explicit user request.
    private var requestFailureMessage: String?

    /// The extension build version embedded in the current application bundle.
    private var bundledExtensionVersion: String? {
        let url = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/Library/SystemExtensions/\(VirtualCameraConfiguration.extensionBundleID).systemextension"
        )
        return Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    /// Refreshes system state without installing or activating anything.
    func refresh(
        retryDeviceDiscovery: Bool = false,
        preservingFailure: Bool = true
    ) {
        guard !isShuttingDown else { return }
        synchronizeReadiness()
        guard (!isBusy || isAwaitingApproval), propertiesRequest == nil else { return }
        if !preservingFailure {
            requestFailureMessage = nil
            requestFailure = nil
            queryFailure = nil
        }
        forceDeviceCheck = retryDeviceDiscovery
        let request = OSSystemExtensionRequest.propertiesRequest(
            forExtensionWithIdentifier: VirtualCameraConfiguration.extensionBundleID,
            queue: .main
        )
        propertiesRequest = request
        if operation?.kind != .requestAccess && operation?.kind != .discoverInput {
            propertiesOperationID = operation?.id
        }
        isRefreshing = true
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// Starts the same typed setup workflow used by onboarding and the home notice.
    func install() {
        Task { [weak self] in await self?.perform(.install) }
    }

    /// Removes the camera without scheduling a subsequent reinstall when explicitly requested.
    func uninstall() {
        Task { [weak self] in await self?.perform(.remove) }
    }

    /// Prevents removing a working old camera when this application cannot install its replacement.
    private func validateInstallationLocation() -> Bool {
        guard Bundle.main.bundleURL.resolvingSymlinksInPath().path.hasPrefix("/Applications/"),
            let version = bundledExtensionVersion, !version.isEmpty
        else {
            deviceFailure = .installationLocation
            status = CameraStrings.statusMoveFaceNowToApplicationsBeforeInstallingTheExtension
            return false
        }
        return true
    }

    /// Activates only after the workflow has confirmed that no obsolete installation remains.
    private func activateExtension() {
        guard validateInstallationLocation() else {
            finishOperation(operation?.id)
            return
        }
        submit(
            OSSystemExtensionRequest.activationRequest(
                forExtensionWithIdentifier: VirtualCameraConfiguration.extensionBundleID,
                queue: .main
            ),
            kind: .activation
        )
    }

    /// Submits the removal stage while keeping the durable reinstall intent intact.
    private func deactivateExtension() {
        submit(
            OSSystemExtensionRequest.deactivationRequest(
                forExtensionWithIdentifier: VirtualCameraConfiguration.extensionBundleID,
                queue: .main
            ),
            kind: .deactivation
        )
    }

    /// Continues a previously authorized workflow only after a successful installation-properties query.
    private func resumeSetup(
        records: [VirtualCameraInstallationState.Record]
    ) -> Bool {
        guard pendingRequest == nil, !isBusy, var workflow = setupWorkflow else { return false }
        let next = workflow.reconcile(
            hasRecords: !records.isEmpty,
            hasCurrentRecord: records.contains { $0.version == workflow.targetVersion && !$0.isUninstalling },
            onlyUninstalling: !records.isEmpty && records.allSatisfy(\.isUninstalling),
            bootID: bootID
        )
        setupWorkflow = workflow
        switch next {
        case .install:
            isSystemCompletionPending = false
            operationFailure = nil
            requestFailure = nil
            requestFailureMessage = nil
            operation = CameraOperationContext(kind: .install, origin: .user)
            activateExtension()
            return true
        case .waitForSystem:
            cancelDeviceWait()
            isSystemCompletionPending = true
            status = CameraStrings.statusInstallationIncomplete
            return true
        case .manualRemoval:
            isSystemCompletionPending = false
            let failure =
                workflow.failure
                ?? CameraOperationFailure(
                    operation: .remove,
                    kind: .missingExtensionRecord,
                    diagnosticMessage:
                        "The previous camera extension is still registered. Remove it in System Settings."
                )
            operationFailure = failure
            requestFailure = failure
            return true
        case .verify:
            isSystemCompletionPending = false
            if requestFailure?.operation == .remove {
                requestFailure = nil
                operationFailure = nil
            }
            return false
        case .none:
            isSystemCompletionPending = false
            requestFailure = workflow.failure
            operationFailure = workflow.failure
            return workflow.failure != nil
        }
    }

    /// Targets Camera Extensions directly, with a fallback for unavailable settings destinations.
    func openSettings() {
        let destinations: [String]
        if #available(macOS 15, *) {
            destinations = [
                "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.system_extension.cmio.extension-point",
                "x-apple.systempreferences:com.apple.LoginItems-Settings.extension?ExtensionItems",
                "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            ]
        } else {
            destinations = ["x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"]
        }
        for destination in destinations {
            if let url = URL(string: destination), NSWorkspace.shared.open(url) { return }
        }
    }

    /// Starts a request on the main queue and keeps controls stable until it finishes.
    private func submit(
        _ request: OSSystemExtensionRequest,
        kind: RequestKind
    ) {
        guard !isShuttingDown, pendingRequest == nil, !isBusy, !isRefreshing else { return }
        cancelDiscoveryComparison()
        cancelDeviceWait()
        readinessPolicy.reset()
        requestFailureMessage = nil
        requestFailure = nil
        queryFailure = nil
        deviceFailure = nil
        isSystemCompletionPending = false
        isBusy = true
        isAwaitingApproval = false
        pendingRequest = request
        pendingKind = kind
        pendingOperationKind = kind == .deactivation ? .remove : .install
        pendingOperationID = operation?.id
        status =
            kind == .deactivation
            ? CameraStrings.statusRemovingVirtualCamera : CameraStrings.statusInstallingCameraExtension
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        requestTimeoutTask?.cancel()
        let requestID = ObjectIdentifier(request)
        requestTimeoutTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, !self.isShuttingDown,
                self.pendingRequest.map(ObjectIdentifier.init) == requestID,
                !self.isAwaitingApproval
            else { return }
            let failure = CameraOperationFailure(
                operation: self.pendingOperationKind,
                kind: .pendingRequest,
                diagnosticMessage:
                    "macOS has not completed the extension request. Review Camera Extensions before continuing."
            )
            self.requestFailure = failure
            self.operationFailure = failure
            if var workflow = self.setupWorkflow {
                workflow.failure = failure
                self.setupWorkflow = workflow
            }
            self.isBusy = false
            self.finishOperation(self.pendingOperationID)
            self.requestTimeoutTask = nil
        }
    }

    /// Rejects an obsolete-version race instead of falling back to an in-place replacement.
    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        guard existing.bundleVersion == ext.bundleVersion,
            existing.bundleShortVersion == ext.bundleShortVersion
        else {
            let requestID = ObjectIdentifier(request)
            replacementConflicts.withLock { _ = $0.insert(requestID) }
            return .cancel
        }
        return .replace
    }

    /// Keeps the request pending while the user grants macOS approval.
    nonisolated func requestNeedsUserApproval(
        _ request: OSSystemExtensionRequest
    ) {
        let identifier = ObjectIdentifier(request)
        Task { @MainActor in
            guard self.pendingRequest.map(ObjectIdentifier.init) == identifier else { return }
            self.requestTimeoutTask?.cancel()
            self.requestTimeoutTask = nil
            self.isAwaitingApproval = true
            self.status =
                CameraStrings.statusEnableFaceNowXmaxVirtualCameraInSystemSettingsGeneral
        }
    }

    /// Reports request completion and checks whether the camera is enabled.
    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        let identifier = ObjectIdentifier(request)
        Task { @MainActor in
            guard self.pendingRequest.map(ObjectIdentifier.init) == identifier else { return }
            self.requestTimeoutTask?.cancel()
            self.requestTimeoutTask = nil
            let activated = self.pendingKind == .activation && result == .completed
            if var workflow = self.setupWorkflow {
                if self.pendingKind == .deactivation {
                    workflow.removalCompleted(needsRestart: result == .willCompleteAfterReboot, bootID: self.bootID)
                } else {
                    workflow.installationCompleted(
                        needsRestart: result == .willCompleteAfterReboot,
                        bootID: self.bootID
                    )
                }
                self.setupWorkflow = workflow
            }
            let operationID = self.pendingOperationID
            self.pendingOperationID = nil
            if activated {
                self.deferDiscoveryUntilActivation = false
                self.logger.notice("Camera activation completed before starting deferred discovery")
            }
            self.pendingRequest = nil
            self.pendingKind = nil
            self.isBusy = false
            self.isAwaitingApproval = false
            self.propertiesRequest = nil
            self.isRefreshing = false
            self.isSystemCompletionPending = result == .willCompleteAfterReboot
            if self.isSystemCompletionPending {
                self.cancelDeviceWait()
                self.status = CameraStrings.statusInstallationIncomplete
                self.finishOperation(operationID)
            } else {
                self.diagnoseAfterReadiness = activated && VirtualCameraDiagnostics.activationRequested
                self.status = CameraStrings.statusRequestCompleted
                self.refresh()
            }
        }
    }

    /// Reports setup failures without treating a missing extension as installed.
    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        didFailWithError error: Error
    ) {
        let message = error.localizedDescription
        let systemError = error as NSError
        let errorDomain = systemError.domain
        let errorCode = systemError.code
        let identifier = ObjectIdentifier(request)
        let replacementConflict = replacementConflicts.withLock { $0.remove(identifier) != nil }
        Task { @MainActor in
            if self.propertiesRequest.map(ObjectIdentifier.init) == identifier {
                let operationID = self.propertiesOperationID
                self.propertiesOperationID = nil
                self.propertiesRequest = nil
                self.queryFailure = CameraOperationFailure(
                    operation: .checkStatus,
                    diagnosticMessage: message,
                    errorDomain: errorDomain,
                    errorCode: errorCode
                )
                self.isRefreshing = false
                if !self.isBusy, !self.isSystemCompletionPending { self.status = self.requestFailureMessage ?? message }
                if let operationID, self.operation?.id == operationID {
                    self.operationFailure = self.queryFailure
                }
                if !self.isBusy { self.finishOperation(operationID) }
                return
            }
            guard self.pendingRequest.map(ObjectIdentifier.init) == identifier else { return }
            self.requestTimeoutTask?.cancel()
            self.requestTimeoutTask = nil
            let removal = self.pendingKind == .deactivation
            let operationID = self.pendingOperationID
            self.pendingOperationID = nil
            let failure: String
            self.logger.error(
                "Camera extension request failed: \(errorDomain, privacy: .public) (\(errorCode)): \(message, privacy: .public)"
            )
            if removal, errorDomain == OSSystemExtensionErrorDomain,
                errorCode == OSSystemExtensionError.Code.extensionNotFound.rawValue
            {
                failure =
                    CameraStrings.removalMismatch
            } else {
                failure =
                    removal
                    ? CameraStrings.removalFailed(message: message) : CameraStrings.installationFailed(message: message)
            }
            self.pendingRequest = nil
            self.pendingKind = nil
            self.isBusy = false
            self.isAwaitingApproval = false
            self.propertiesRequest = nil
            self.isRefreshing = false
            self.requestFailureMessage = failure
            self.requestFailure = CameraOperationFailure.systemExtension(
                operation: self.pendingOperationKind,
                domain: errorDomain,
                code: errorCode,
                message: message
            )
            if self.requestFailure?.kind == .invalidLocation,
                Bundle.main.bundleURL.resolvingSymlinksInPath().path.hasPrefix("/Applications/")
            {
                self.requestFailure?.kind = .system
            }
            if replacementConflict {
                self.requestFailure = CameraOperationFailure(
                    operation: .remove,
                    kind: .missingExtensionRecord,
                    diagnosticMessage: "Another extension version remained registered after removal.",
                    errorDomain: errorDomain,
                    errorCode: errorCode
                )
            }
            self.operationFailure = self.requestFailure
            if var workflow = self.setupWorkflow {
                let kind = self.requestFailure?.kind
                let isFatal = kind == .invalidBundle || kind == .systemPolicy || kind == .invalidLocation
                workflow.phase = (removal || replacementConflict) && !isFatal ? .manualRemoval : .failed
                workflow.failure = self.requestFailure
                self.setupWorkflow = workflow
            }
            self.status = failure
            self.finishOperation(operationID)
            self.refresh(preservingFailure: true)
        }
    }

    /// Refreshes enabled state from macOS rather than persisting a guessed install flag.
    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        foundProperties properties: [OSSystemExtensionProperties]
    ) {
        let records = properties.map {
            VirtualCameraInstallationState.Record(
                version: $0.bundleVersion,
                isEnabled: $0.isEnabled,
                isUninstalling: $0.isUninstalling
            )
        }
        let identifier = ObjectIdentifier(request)
        Task { @MainActor in
            guard self.propertiesRequest.map(ObjectIdentifier.init) == identifier else { return }
            let operationID = self.propertiesOperationID
            self.propertiesOperationID = nil
            defer {
                self.synchronizeReadiness()
                if self.isWaitingForDevice {
                    if let operationID, self.operation?.id == operationID {
                        self.readinessOperationID = operationID
                    }
                } else if !self.isBusy {
                    self.finishOperation(operationID)
                }
            }
            self.propertiesRequest = nil
            self.queryFailure = nil
            self.hasCheckedInstallation = true
            self.isInstalled = !records.isEmpty
            self.isRefreshing = false
            let installation = VirtualCameraInstallationState(
                records: records,
                bundledVersion: self.bundledExtensionVersion
            )
            let enabled = installation.isEnabled
            let current = installation.isVersionCurrent
            let version = installation.enabledVersions.sorted().joined(separator: ",")
            self.isEnabled = enabled
            self.isVersionCurrent = current
            if self.operationFailure?.operation == .checkStatus
                || (self.operationFailure?.operation == .remove && !self.isInstalled)
            {
                self.operationFailure = nil
            }
            if self.requestFailure?.operation == .remove, !self.isInstalled {
                self.requestFailure = nil
                self.requestFailureMessage = nil
            }
            // A persisted restart boundary may be crossed only after a real reboot and fresh properties.
            if self.resumeSetup(records: records) { return }
            if current, self.setupWorkflow == nil { self.isSystemCompletionPending = false }
            // An already-enabled old version must not complete approval for its replacement.
            guard !self.isBusy, !self.isSystemCompletionPending else { return }
            if installation.requiresRestartForRemoval {
                self.cancelDeviceWait()
                self.isSystemCompletionPending = true
                self.status = CameraStrings.statusInstallationIncomplete
                return
            }
            if enabled, !current {
                self.cancelDeviceWait()
                self.status =
                    self.requestFailureMessage ?? CameraStrings.statusUpdateVirtualCameraToMatchThisVersionOfFaceNow
                return
            }
            if enabled {
                if self.deferDiscoveryUntilActivation {
                    self.deviceFailure = .activationRequired
                    self.status =
                        self.requestFailureMessage
                        ?? CameraStrings.statusCameraExtensionEnabledClickUpdateToTestActivation
                    return
                }
                if self.readinessPolicy.shouldCheck(
                    version: version,
                    force: self.forceDeviceCheck
                ) {
                    self.cancelDeviceWait(preservingReadiness: self.isDeviceReady)
                    self.waitForDevice()
                }
            } else {
                self.cancelDiscoveryComparison()
                self.cancelDeviceWait()
                self.readinessPolicy.reset()
                self.status = self.requestFailureMessage ?? CameraStrings.statusCameraExtensionNotEnabled
            }
            self.forceDeviceCheck = false
        }
    }

    /// Checks the actual CMIO sink after activation, rather than equating enabled with usable.
    private func waitForDevice() {
        guard !isShuttingDown, readinessTask == nil else { return }
        let id = UUID()
        readinessID = id
        readinessOperationID = operation?.id
        deviceFailure = nil
        isWaitingForDevice = true
        status = requestFailureMessage ?? CameraStrings.statusCameraExtensionEnabledWaitingForTheCameraToBecome
        readinessTask = Task { [weak self] in
            do {
                if !VirtualCameraDeviceMonitor.shared.isStarted {
                    let executable = try VirtualCameraDiagnostics.helperExecutable()
                    try await VirtualCameraDiagnostics.waitForPublication(executable: executable)
                    guard let self, self.readinessID == id, !Task.isCancelled else { return }
                    self.logger.notice(
                        "Fresh process confirmed camera publication before host discovery startup"
                    )
                    VirtualCameraDeviceMonitor.shared.start()
                }
                _ = try await VirtualCameraDiscovery.waitForSink()
                guard let self, self.readinessID == id, !Task.isCancelled else { return }
                self.logger.notice("Virtual camera sink discovered after enabled-state verification")
                self.deviceFailure = nil
                self.isDeviceReady = true
                let completedSetup = self.setupWorkflow != nil
                self.setupWorkflow = nil
                self.deviceRecovery = nil
                if completedSetup || self.operationFailure?.operation != .remove { self.operationFailure = nil }
                if completedSetup || self.requestFailure?.operation != .remove {
                    self.requestFailure = nil
                    self.requestFailureMessage = nil
                }
                self.status = self.requestFailureMessage ?? CameraStrings.statusVirtualCameraReady
                self.isWaitingForDevice = false
                self.readinessTask = nil
                self.finishOperation(self.readinessOperationID)
                self.readinessOperationID = nil
                self.compareDiscoveryIfRequested()
            } catch {
                guard let self, self.readinessID == id, !Task.isCancelled else { return }
                var reason: CameraUnavailableReason = .operationFailed(
                    CameraOperationFailure(operation: .discoverOutput, diagnosticMessage: error.localizedDescription)
                )
                if error is VirtualCameraDiscovery.DiscoveryError {
                    reason = .devicePublicationTimedOut
                }
                var message = CameraStrings.notReady(message: error.localizedDescription)
                if VirtualCameraDeviceMonitor.shared.isStarted,
                    let executable = try? VirtualCameraDiagnostics.helperExecutable(),
                    let comparison = try? await VirtualCameraDiagnostics.compare(executable: executable),
                    comparison.assessment == .possibleStaleHost
                {
                    reason = .reopenApplication
                    message =
                        CameraStrings.statusMacOSHasRefreshedTheCameraButFaceNowStillHas
                }
                guard self.readinessID == id, !Task.isCancelled else { return }
                if reason == .devicePublicationTimedOut || reason == .reopenApplication {
                    let recovery =
                        self.deviceRecovery
                        ?? CameraDeviceRecovery(
                            targetVersion: self.bundledExtensionVersion ?? "",
                            initialBootID: self.bootID
                        )
                    self.deviceRecovery = recovery
                    switch recovery.nextStep(
                        bootID: self.bootID,
                        processID: ProcessInfo.processInfo.processIdentifier,
                        staleHost: reason == .reopenApplication
                    ) {
                    case .restartApplication: reason = .reopenApplication
                    case .toggleExtension: reason = .devicePublicationTimedOut
                    case .install: reason = .installationIncomplete
                    }
                }
                self.deviceFailure = reason
                if case .operationFailed(let failure) = reason {
                    self.operationFailure = failure
                }
                self.isDeviceReady = false
                self.status = self.requestFailureMessage ?? message
                self.logger.error("Camera readiness failed: \(message, privacy: .public)")
                self.isWaitingForDevice = false
                self.readinessTask = nil
                self.finishOperation(self.readinessOperationID)
                self.readinessOperationID = nil
                self.compareDiscoveryIfRequested()
            }
        }
    }

    /// Cancels superseded work while optionally retaining an already-verified producer sink.
    private func cancelDeviceWait(
        preservingReadiness: Bool = false
    ) {
        readinessID = UUID()
        readinessTask?.cancel()
        readinessTask = nil
        isWaitingForDevice = false
        if !preservingReadiness {
            isDeviceReady = false
            deviceFailure = nil
        }
    }

    /// Invalidates and cancels the pending optional discovery diagnostic.
    private func cancelDiscoveryComparison() {
        diagnosticID = UUID()
        diagnoseAfterReadiness = false
        diagnosticTask?.cancel()
        diagnosticTask = nil
    }

    /// Opt-in diagnostics leave normal startup and the user's camera stream unchanged.
    private func compareDiscoveryIfRequested() {
        guard diagnoseAfterReadiness, diagnosticTask == nil else { return }
        diagnoseAfterReadiness = false
        let id = UUID()
        diagnosticID = id
        diagnosticTask = Task { [weak self] in
            do {
                let executable = try VirtualCameraDiagnostics.helperExecutable()
                let comparison = try await VirtualCameraDiagnostics.compare(executable: executable)
                guard let self, self.diagnosticID == id, !Task.isCancelled else { return }
                let report = String(
                    decoding: try comparison.reportData(),
                    as: UTF8.self
                )
                self.logger.notice("Camera discovery comparison: \(report, privacy: .public)")
                self.diagnosticTask = nil
            } catch {
                guard let self, self.diagnosticID == id, !Task.isCancelled else { return }
                self.logger.error("Camera discovery comparison failed: \(error.localizedDescription, privacy: .public)")
                self.diagnosticTask = nil
            }
        }
    }

    /// Cancels device-readiness and diagnostic tasks when the extension owner is released.
    isolated deinit {
        requestTimeoutTask?.cancel()
        readinessTask?.cancel()
        diagnosticTask?.cancel()
    }

    /// Distinguishes a status query from an operation that needs a subsequent refresh.
    private enum RequestKind {

        /// Installs or replaces the bundled virtual-camera extension.
        case activation

        /// Removes the virtual-camera extension from the system.
        case deactivation
    }
}

extension Container {

    /// The shared VirtualCamera repository registered for this container.
    @MainActor
    var virtualCameraRepo: Factory<VirtualCameraRepository> {
        Factory(self) { @MainActor in VirtualCameraRepository() }.singleton
    }
}
