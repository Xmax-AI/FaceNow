@preconcurrency import CoreMediaIO
@preconcurrency import AVFoundation
import Combine
import Foundation
import os

/// Owns hardware discovery, started explicitly after the extension is enabled.
@MainActor
final class CameraDeviceMonitor {
    static let shared = CameraDeviceMonitor()
    nonisolated static let didChange = Notification.Name("FaceNow.CameraDevicesChanged")
    let changes = PassthroughSubject<Void, Never>()
    private var discovery: AVCaptureDevice.DiscoverySession?
    private(set) var isStarted = false
    private var observation: NSKeyValueObservation?
    private var notifications: [NSObjectProtocol] = []
    private var cmioListener: CMIOObjectPropertyListenerBlock?
    private let logger = Logger(subsystem: CameraConfiguration.appBundleID, category: "Discovery")

    var devices: [AVCaptureDevice] { discovery?.devices ?? [] }

    private init() {}

    /// Constructing controllers or reading an empty picker must not initialize the hardware list.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown], mediaType: .video, position: .unspecified
        )
        observation = discovery?.observe(\.devices, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.changed(reason: "AVFoundation device list") }
        }
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.changed(reason: name.rawValue) }
            })
        }
        var address = Self.deviceAddress
        let listener: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.changed(reason: "CMIO device list") }
        }
        let status = CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, .main, listener)
        if status == noErr { cmioListener = listener }
        logger.notice("Persistent device monitoring started; CMIO listener status=\(status)")
    }

    private static var deviceAddress: CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: UInt32(kCMIOHardwarePropertyDevices),
                                  mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
                                  mElement: UInt32(kCMIOObjectPropertyElementMain))
    }

    private func changed(reason: String) {
        let visible = devices.contains { $0.uniqueID.caseInsensitiveCompare(CameraConfiguration.deviceID.uuidString) == .orderedSame }
        logger.notice("Device discovery event: \(reason, privacy: .public); virtual camera visible=\(visible)")
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        changes.send(())
    }

    isolated deinit {
        observation?.invalidate()
        notifications.forEach(NotificationCenter.default.removeObserver)
        if let cmioListener {
            var address = Self.deviceAddress
            CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, .main, cmioListener)
        }
    }
}

/// Discovers the producer sink independently of the system extension's activation state.
enum VirtualCameraDiscovery {
    struct Sink: Codable, Equatable, Sendable {
        let device: CMIODeviceID
        let stream: CMIOStreamID
    }

    struct QueryFailure: Codable, LocalizedError, Sendable {
        let operation: String
        let object: CMIOObjectID
        let status: Int32

        var errorDescription: String? { "\(operation) failed for object \(object): OSStatus \(status)" }
    }

    /// Records only counts and this app's virtual device, never camera names or video contents.
    struct Snapshot: Codable, Sendable {
        var processID: Int32 = ProcessInfo.processInfo.processIdentifier
        var uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
        var deviceCount = 0
        var virtualDevice: CMIODeviceID?
        var outputStreams: [CMIOStreamID] = []
        var sink: Sink?
        var failures: [QueryFailure] = []
    }

    private static let logger = Logger(subsystem: CameraConfiguration.appBundleID, category: "Discovery")

    enum DiscoveryError: LocalizedError {
        case timedOut
        var errorDescription: String? {
            "The virtual camera is not ready. Please restart FaceNow."
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
            forName: CameraDeviceMonitor.didChange, object: nil, queue: nil
        ) { _ in continuation.yield(()) }
        var address = CMIOObjectPropertyAddress(
            mSelector: UInt32(kCMIOHardwarePropertyDevices),
            mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
            mElement: UInt32(kCMIOObjectPropertyElementMain)
        )
        let listener: CMIOObjectPropertyListenerBlock = { _, _ in continuation.yield(()) }
        let registered = CMIOObjectAddPropertyListenerBlock(
            CMIOObjectID(kCMIOObjectSystemObject), &address, queue, listener
        ) == noErr
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: pollInterval)
        timer.setEventHandler { continuation.yield(()) }
        timer.resume()
        defer {
            NotificationCenter.default.removeObserver(notification)
            timer.cancel()
            if registered {
                CMIOObjectRemovePropertyListenerBlock(
                    CMIOObjectID(kCMIOObjectSystemObject), &address, queue, listener
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

    static func findSink() throws -> Sink? {
        let result = snapshot()
        if let sink = result.sink { return sink }
        if let failure = result.failures.first { throw failure }
        return nil
    }

    static func snapshot() -> Snapshot {
        var result = Snapshot()
        let devices: [CMIOObjectID]
        do {
            devices = try objectIDs(CMIOObjectID(kCMIOObjectSystemObject), selector: UInt32(kCMIOHardwarePropertyDevices))
            result.deviceCount = devices.count
        } catch {
            result.failures.append(QueryFailure(operation: "device list", object: CMIOObjectID(kCMIOObjectSystemObject),
                                                status: Int32((error as NSError).code)))
            return result
        }
        for device in devices {
            var address = CMIOObjectPropertyAddress(
                mSelector: UInt32(kCMIODevicePropertyDeviceUID),
                mScope: UInt32(kCMIOObjectPropertyScopeGlobal), mElement: UInt32(kCMIOObjectPropertyElementMain)
            )
            var uid: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<CFString>.size)
            let status = CMIOObjectGetPropertyData(device, &address, 0, nil, size, &size, &uid)
            guard status == noErr else {
                result.failures.append(QueryFailure(operation: "device UID", object: device, status: status))
                continue
            }
            guard let value = uid?.takeRetainedValue(),
                  (value as String).caseInsensitiveCompare(CameraConfiguration.deviceID.uuidString) == .orderedSame else { continue }
            result.virtualDevice = device
            do {
                result.outputStreams = try objectIDs(device, selector: UInt32(kCMIODevicePropertyStreams),
                                                     scope: UInt32(kCMIODevicePropertyScopeOutput))
            } catch {
                result.failures.append(QueryFailure(operation: "output streams", object: device,
                                                    status: Int32((error as NSError).code)))
                return result
            }
            for stream in result.outputStreams {
                var directionAddress = CMIOObjectPropertyAddress(
                    mSelector: UInt32(kCMIOStreamPropertyDirection),
                    mScope: UInt32(kCMIOObjectPropertyScopeGlobal), mElement: UInt32(kCMIOObjectPropertyElementMain)
                )
                var direction: UInt32 = 1
                var directionSize: UInt32 = 4
                let status = CMIOObjectGetPropertyData(stream, &directionAddress, 0, nil, directionSize, &directionSize, &direction)
                if status != noErr {
                    result.failures.append(QueryFailure(operation: "stream direction", object: stream, status: status))
                } else if direction == 0 {
                    result.sink = Sink(device: device, stream: stream)
                    return result
                }
            }
            return result
        }
        return result
    }

    private static func objectIDs(
        _ object: CMIOObjectID, selector: CMIOObjectPropertySelector,
        scope: CMIOObjectPropertyScope = UInt32(kCMIOObjectPropertyScopeGlobal)
    ) throws -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: UInt32(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        let sizeStatus = CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &size)
        guard sizeStatus == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(sizeStatus)) }
        var values = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        guard !values.isEmpty else { return [] }
        let status = values.withUnsafeMutableBytes {
            CMIOObjectGetPropertyData(object, &address, 0, nil, size, &size, $0.baseAddress!)
        }
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return Array(values.prefix(Int(size) / MemoryLayout<CMIOObjectID>.size))
    }
}

/// Ordinary status refreshes must not repeatedly restart a completed or timed-out readiness check.
struct CameraReadinessPolicy {
    private var checkedVersion: String?

    mutating func shouldCheck(version: String, force: Bool = false) -> Bool {
        guard force || checkedVersion != version else { return false }
        checkedVersion = version
        return true
    }

    mutating func reset() { checkedVersion = nil }
}
