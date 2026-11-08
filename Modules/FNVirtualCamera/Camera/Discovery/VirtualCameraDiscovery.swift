//
//  VirtualCameraDiscovery.swift
//  FaceNow
//

@preconcurrency import CoreMediaIO
@preconcurrency import AVFoundation
import Combine
import Foundation
import os

/// Owns hardware discovery, started explicitly after the extension is enabled.
@MainActor
final class VirtualCameraDeviceMonitor {

    /// The main-actor device publisher shared by camera readiness and generation.
    static let shared = VirtualCameraDeviceMonitor()

    /// The cross-component notification that wakes pending discovery without opening streams.
    nonisolated static let didChange = Notification.Name("FaceNow.CameraDevicesChanged")

    /// The main-actor device-change signal consumed by business repositories.
    let changes = PassthroughSubject<Void, Never>()

    /// The hardware discovery session, created only after explicit startup.
    private var discovery: AVCaptureDevice.DiscoverySession?

    /// Whether device enumeration and publication listeners have been installed.
    private(set) var isStarted = false

    /// The retained observation of AVFoundation device publication.
    private var observation: NSKeyValueObservation?

    /// The connection and disconnection observers removed during teardown.
    private var notifications: [NSObjectProtocol] = []

    /// The registered CMIO listener retained until it can be removed with the same block.
    private var cmioListener: CMIOObjectPropertyListenerBlock?

    /// The discovery logger recording availability without video contents.
    private let logger = Logger(
        subsystem: VirtualCameraConfiguration.appBundleID,
        category: "Discovery"
    )

    /// The currently published video devices, empty before monitoring starts.
    var devices: [AVCaptureDevice] { discovery?.devices ?? [] }

    /// Creates an idle monitor without enumerating hardware or starting capture.
    private init() {}

    /// Starts shared discovery for authorized home selection, helper confirmation, or an explicit preview action.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )
        observation = discovery?.observe(
            \.devices,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.changed(reason: "AVFoundation device list") }
        }
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            notifications.append(
                NotificationCenter.default.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.changed(reason: name.rawValue) }
                }
            )
        }
        var address = Self.deviceAddress
        let listener: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.changed(reason: "CMIO device list") }
        }
        let status = CMIOObjectAddPropertyListenerBlock(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address,
            .main,
            listener
        )
        if status == noErr { cmioListener = listener }
        logger.notice("Persistent device monitoring started; CMIO listener status=\(status)")
    }

    /// The CMIO system property describing the process-visible device list.
    private static var deviceAddress: CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: UInt32(kCMIOHardwarePropertyDevices),
            mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
            mElement: UInt32(kCMIOObjectPropertyElementMain)
        )
    }

    /// Publishes discovery changes and records whether this app's camera is visible.
    private func changed(
        reason: String
    ) {
        let visible = devices.contains {
            $0.uniqueID.caseInsensitiveCompare(VirtualCameraConfiguration.deviceID.uuidString) == .orderedSame
        }
        logger.notice("Device discovery event: \(reason, privacy: .public); virtual camera visible=\(visible)")
        NotificationCenter.default.post(
            name: Self.didChange,
            object: nil
        )
        changes.send(())
    }

    /// Removes retained device observers and the matching CMIO listener.
    isolated deinit {
        observation?.invalidate()
        notifications.forEach(NotificationCenter.default.removeObserver)
        if let cmioListener {
            var address = Self.deviceAddress
            CMIOObjectRemovePropertyListenerBlock(
                CMIOObjectID(kCMIOObjectSystemObject),
                &address,
                .main,
                cmioListener
            )
        }
    }
}

/// Discovers the producer sink independently of the system extension's activation state.
enum VirtualCameraDiscovery {

    /// The process-local CMIO device and stream selected for producer output.
    struct Sink: Codable, Equatable, Sendable {

        /// The process-local virtual device identifier.
        let device: CMIODeviceID

        /// The process-local producer sink identifier.
        let stream: CMIOStreamID
    }

    /// Captures a failed CMIO property query without exposing camera names.
    struct QueryFailure: Codable, LocalizedError, Sendable {

        /// The property operation that failed.
        let operation: String

        /// The process-local CMIO object queried by the operation.
        let object: CMIOObjectID

        /// The OSStatus returned by the failed framework call.
        let status: Int32

        /// A diagnostic description containing the operation, object, and status.
        var errorDescription: String? { "\(operation) failed for object \(object): OSStatus \(status)" }
    }

    /// Records only counts and this app's virtual device, never camera names or video contents.
    struct Snapshot: Codable, Sendable {

        /// The process that owns all CMIO identifiers in this snapshot.
        var processID: Int32 = ProcessInfo.processInfo.processIdentifier

        /// The monotonic sample time in seconds since system startup.
        var uptime: TimeInterval = ProcessInfo.processInfo.systemUptime

        /// The number of CMIO devices visible to this process.
        var deviceCount = 0

        /// This app's discovered device, absent before publication.
        var virtualDevice: CMIODeviceID?

        /// The stream identifiers published by this app's virtual device.
        var outputStreams: [CMIOStreamID] = []

        /// The usable producer sink, absent when discovery is incomplete.
        var sink: Sink?

        /// The property-query failures encountered while collecting this snapshot.
        var failures: [QueryFailure] = []
    }

    /// The logger for sink-discovery attempts and bounded waiting.
    private static let logger = Logger(
        subsystem: VirtualCameraConfiguration.appBundleID,
        category: "Discovery"
    )

    /// Reports that macOS has not published a usable producer sink in time.
    enum DiscoveryError: LocalizedError {

        /// The bounded discovery deadline expired before a sink became available.
        case timedOut

        /// The recovery instructions shown when camera publication times out.
        var errorDescription: String? {
            "macOS has not published the camera. Install Virtual Camera again, enable FaceNow in Camera Extensions, and return to FaceNow to check the connection."
        }
    }

    /// Device notifications wake discovery immediately; polling also covers delayed stream publication.
    /// Registration happens before the first probe so device arrival cannot be missed.
    static func waitForSink(
        timeout: Duration = .seconds(12),
        pollInterval: DispatchTimeInterval = .milliseconds(250),
        probe: @escaping @Sendable () throws -> Sink? = { try findSink() }
    ) async throws -> Sink {
        try Task.checkCancellation()
        let queue = DispatchQueue(label: "ai.xmax.camera.discovery")
        let (events, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let notification = NotificationCenter.default.addObserver(
            forName: VirtualCameraDeviceMonitor.didChange,
            object: nil,
            queue: nil
        ) { _ in continuation.yield(()) }
        var address = CMIOObjectPropertyAddress(
            mSelector: UInt32(kCMIOHardwarePropertyDevices),
            mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
            mElement: UInt32(kCMIOObjectPropertyElementMain)
        )
        let listener: CMIOObjectPropertyListenerBlock = { _, _ in continuation.yield(()) }
        let registered =
            CMIOObjectAddPropertyListenerBlock(
                CMIOObjectID(kCMIOObjectSystemObject),
                &address,
                queue,
                listener
            ) == noErr
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now(),
            repeating: pollInterval
        )
        timer.setEventHandler { continuation.yield(()) }
        timer.resume()
        defer {
            NotificationCenter.default.removeObserver(notification)
            timer.cancel()
            if registered {
                CMIOObjectRemovePropertyListenerBlock(
                    CMIOObjectID(kCMIOObjectSystemObject),
                    &address,
                    queue,
                    listener
                )
            }
            continuation.finish()
        }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var previousError: String?
        for await _ in events {
            try Task.checkCancellation()
            // Device IDs can disappear between enumeration and reading stream properties during replacement.
            do {
                if let sink = try probe() {
                    try Task.checkCancellation()
                    return sink
                }
                previousError = nil
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let message = error.localizedDescription
                if previousError != message {
                    logger.error("Camera discovery query failed: \(message, privacy: .public)")
                    previousError = message
                }
            }
            if ContinuousClock.now >= deadline { throw DiscoveryError.timedOut }
        }
        throw CancellationError()
    }

    /// Returns this process's usable producer sink or propagates a CMIO query failure.
    static func findSink() throws -> Sink? {
        let result = snapshot()
        if let sink = result.sink { return sink }
        if let failure = result.failures.first { throw failure }
        return nil
    }

    /// Captures process-local discovery availability without opening camera streams.
    static func snapshot() -> Snapshot {
        var result = Snapshot()
        let devices: [CMIOObjectID]
        do {
            devices = try objectIDs(
                CMIOObjectID(kCMIOObjectSystemObject),
                selector: UInt32(kCMIOHardwarePropertyDevices)
            )
            result.deviceCount = devices.count
        } catch {
            result.failures.append(
                QueryFailure(
                    operation: "device list",
                    object: CMIOObjectID(kCMIOObjectSystemObject),
                    status: Int32((error as NSError).code)
                )
            )
            return result
        }
        for device in devices {
            var address = CMIOObjectPropertyAddress(
                mSelector: UInt32(kCMIODevicePropertyDeviceUID),
                mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
                mElement: UInt32(kCMIOObjectPropertyElementMain)
            )
            var uid: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<CFString>.size)
            let status = CMIOObjectGetPropertyData(
                device,
                &address,
                0,
                nil,
                size,
                &size,
                &uid
            )
            guard status == noErr else {
                result.failures.append(
                    QueryFailure(
                        operation: "device UID",
                        object: device,
                        status: status
                    )
                )
                continue
            }
            guard let value = uid?.takeRetainedValue(),
                (value as String).caseInsensitiveCompare(VirtualCameraConfiguration.deviceID.uuidString)
                    == .orderedSame
            else { continue }
            result.virtualDevice = device
            do {
                result.outputStreams = try objectIDs(
                    device,
                    selector: UInt32(kCMIODevicePropertyStreams),
                    scope: UInt32(kCMIODevicePropertyScopeOutput)
                )
            } catch {
                result.failures.append(
                    QueryFailure(
                        operation: "output streams",
                        object: device,
                        status: Int32((error as NSError).code)
                    )
                )
                return result
            }
            for stream in result.outputStreams {
                var directionAddress = CMIOObjectPropertyAddress(
                    mSelector: UInt32(kCMIOStreamPropertyDirection),
                    mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
                    mElement: UInt32(kCMIOObjectPropertyElementMain)
                )
                var direction: UInt32 = 1
                var directionSize: UInt32 = 4
                let status = CMIOObjectGetPropertyData(
                    stream,
                    &directionAddress,
                    0,
                    nil,
                    directionSize,
                    &directionSize,
                    &direction
                )
                if status != noErr {
                    result.failures.append(
                        QueryFailure(
                            operation: "stream direction",
                            object: stream,
                            status: status
                        )
                    )
                } else if direction == 0 {
                    result.sink = Sink(
                        device: device,
                        stream: stream
                    )
                    return result
                }
            }
            return result
        }
        return result
    }

    /// Reads the variable-length object list for one CMIO property address.
    private static func objectIDs(
        _ object: CMIOObjectID,
        selector: CMIOObjectPropertySelector,
        scope: CMIOObjectPropertyScope = UInt32(kCMIOObjectPropertyScopeGlobal)
    ) throws -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: UInt32(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        let sizeStatus = CMIOObjectGetPropertyDataSize(
            object,
            &address,
            0,
            nil,
            &size
        )
        guard sizeStatus == noErr else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(sizeStatus)
            )
        }
        var values = [CMIOObjectID](
            repeating: 0,
            count: Int(size) / MemoryLayout<CMIOObjectID>.size
        )
        guard !values.isEmpty else { return [] }
        let status = values.withUnsafeMutableBytes {
            CMIOObjectGetPropertyData(
                object,
                &address,
                0,
                nil,
                size,
                &size,
                $0.baseAddress!
            )
        }
        guard status == noErr else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status)
            )
        }
        return Array(values.prefix(Int(size) / MemoryLayout<CMIOObjectID>.size))
    }
}

/// Ordinary status refreshes must not repeatedly restart a completed or timed-out readiness check.
struct VirtualCameraReadinessPolicy {

    /// The extension version that has already received a bounded readiness check.
    private var checkedVersion: String?

    /// Allows a new version or explicit retry to start one readiness check.
    mutating func shouldCheck(
        version: String,
        force: Bool = false
    ) -> Bool {
        guard force || checkedVersion != version else { return false }
        checkedVersion = version
        return true
    }

    /// Allows the next extension state to receive a fresh readiness check.
    mutating func reset() { checkedVersion = nil }
}

/// Interprets system records without letting obsolete removal records block an installed camera.
struct VirtualCameraInstallationState: Sendable {

    /// The version and activation flags returned by a system extension properties query.
    struct Record: Sendable {

        /// The build version reported by macOS for this record.
        let version: String

        /// Whether macOS currently enables this extension record.
        let isEnabled: Bool

        /// Whether this record is pending removal, potentially until restart.
        let isUninstalling: Bool
    }

    /// All records returned for the camera extension identifier.
    let records: [Record]

    /// The build version packaged with this application, absent if unreadable.
    let bundledVersion: String?

    /// The enabled versions excluding records already pending removal.
    var enabledVersions: [String] {
        records.filter { $0.isEnabled && !$0.isUninstalling }.map(\.version)
    }

    /// Whether any active extension record remains installed.
    var isEnabled: Bool { !enabledVersions.isEmpty }

    /// Whether an active extension record matches the bundled build.
    var isVersionCurrent: Bool { bundledVersion.map(enabledVersions.contains) ?? false }

    /// Whether all remaining records are pending removal and require restart.
    var requiresRestartForRemoval: Bool {
        !records.isEmpty && records.allSatisfy(\.isUninstalling)
    }
}
