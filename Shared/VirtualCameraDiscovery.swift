@preconcurrency import CoreMediaIO
@preconcurrency import AVFoundation
import Combine
import Foundation
import os

/// Keeps AVFoundation discovery and CMIO notifications alive before extension registration.
@MainActor
final class CameraDeviceMonitor {
    static let shared = CameraDeviceMonitor()
    nonisolated static let didChange = Notification.Name("FaceNow.CameraDevicesChanged")
    let changes = PassthroughSubject<Void, Never>()
    private let discovery: AVCaptureDevice.DiscoverySession
    private var observation: NSKeyValueObservation?
    private var notifications: [NSObjectProtocol] = []
    private var cmioListener: CMIOObjectPropertyListenerBlock?
    private let logger = Logger(subsystem: CameraConfiguration.appBundleID, category: "Discovery")

    var devices: [AVCaptureDevice] { discovery.devices }

    private init() {
        discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown], mediaType: .video, position: .unspecified
        )
        observation = discovery.observe(\.devices, options: [.initial, .new]) { [weak self] _, _ in
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
    struct Sink: Equatable, Sendable {
        let device: CMIODeviceID
        let stream: CMIOStreamID
    }

    enum DiscoveryError: LocalizedError {
        case timedOut
        var errorDescription: String? {
            "The virtual camera is not ready yet. Check Virtual Camera settings and try again."
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
        for await _ in events {
            try Task.checkCancellation()
            // Device IDs can disappear between enumeration and reading stream properties during replacement.
            if let sink = try? probe() {
                try Task.checkCancellation()
                return sink
            }
            if ContinuousClock.now >= deadline { throw DiscoveryError.timedOut }
        }
        throw CancellationError()
    }

    static func findSink() throws -> Sink? {
        for device in try objectIDs(CMIOObjectID(kCMIOObjectSystemObject), selector: UInt32(kCMIOHardwarePropertyDevices)) {
            var address = CMIOObjectPropertyAddress(
                mSelector: UInt32(kCMIODevicePropertyDeviceUID),
                mScope: UInt32(kCMIOObjectPropertyScopeGlobal), mElement: UInt32(kCMIOObjectPropertyElementMain)
            )
            var uid: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<CFString>.size)
            guard CMIOObjectGetPropertyData(device, &address, 0, nil, size, &size, &uid) == noErr,
                  let value = uid?.takeRetainedValue(),
                  (value as String).caseInsensitiveCompare(CameraConfiguration.deviceID.uuidString) == .orderedSame else { continue }
            for stream in try objectIDs(device, selector: UInt32(kCMIODevicePropertyStreams), scope: UInt32(kCMIODevicePropertyScopeOutput)) {
                var directionAddress = CMIOObjectPropertyAddress(
                    mSelector: UInt32(kCMIOStreamPropertyDirection),
                    mScope: UInt32(kCMIOObjectPropertyScopeGlobal), mElement: UInt32(kCMIOObjectPropertyElementMain)
                )
                var direction: UInt32 = 1
                var directionSize: UInt32 = 4
                if CMIOObjectGetPropertyData(stream, &directionAddress, 0, nil, directionSize, &directionSize, &direction) == noErr,
                   direction == 0 { return Sink(device: device, stream: stream) }
            }
        }
        return nil
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
