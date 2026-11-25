//
//  PlaybackEchoCancellation.swift
//  FaceNow
//

import Combine
import CoreAudio
import CoreMedia
import Foundation
import XmaxSDK
import os

/// The audio output route selected for local acoustic echo cancellation.
struct EchoPlaybackDevice: Equatable, Sendable {

    let id: AudioDeviceID
    let uid: String
    let name: String
}

/// Owns the opt-in setting and switches reference captures as the output route changes.
@MainActor
final class PlaybackEchoCancellation: ObservableObject {

    enum Status: Equatable {
        case off
        case waitingForMicrophone
        case starting
        case waitingForReference
        case listening
        case noDevice
        case unavailable
        case failed
    }

    private static let enabledKey = "generation.echoCancellation.enabled"
    private static let deviceKey = "generation.echoCancellation.playbackDevice"

    let processor = MicrophoneEchoProcessor()
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: enabledKey)
    @Published private(set) var deviceUID = UserDefaults.standard.string(forKey: deviceKey)
    @Published private(set) var devices: [EchoPlaybackDevice] = []
    @Published private(set) var status: Status = .off

    private let worker = PlaybackEchoWorker()
    private let logger = Logger(subsystem: "ai.xmax.FaceNow", category: "EchoCancellation")
    private var defaultDevice: AudioDeviceID = kAudioObjectUnknown
    private var usingMicrophone = false
    private var target: EchoPlaybackDevice?
    private var revision = UUID()
    private var referenceMonitor: Task<Void, Never>?


    var isSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    init() {
        guard isSupported else {
            status = .unavailable
            return
        }
        worker.observeRoutes { [weak self] devices, defaultDevice, invalidatedDevice in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.devices != devices { self.devices = devices }
                self.defaultDevice = defaultDevice
                self.reconcile(force: invalidatedDevice.map { $0 == self.target?.id } ?? false)
            }
        }
    }

    func setEnabled(
        _ enabled: Bool
    ) {
        guard isSupported, self.enabled != enabled else { return }
        self.enabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        reconcile()
    }

    func selectDevice(
        _ uid: String?
    ) {
        guard uid != deviceUID else { return }
        deviceUID = uid
        UserDefaults.standard.set(uid, forKey: Self.deviceKey)
        reconcile()
    }

    /// Ties system-audio access to the session that owns the SDK microphone.
    func setMicrophoneActive(
        _ active: Bool
    ) {
        guard usingMicrophone != active else { return }
        usingMicrophone = active
        reconcile()
    }

    /// Microphone changes invalidate the adaptive filter even if playback stays on the same device.
    func microphoneChanged() {
        processor.invalidateCalibration()
    }

    private func reconcile(
        force: Bool = false
    ) {
        guard #available(macOS 14.2, *) else { return }
        guard enabled else {
            stop(status: .off)
            return
        }
        guard usingMicrophone else {
            stop(status: .waitingForMicrophone)
            return
        }
        let device = if let deviceUID {
            devices.first { $0.uid == deviceUID }
        } else {
            devices.first { $0.id == defaultDevice }
        }
        guard let device else {
            stop(status: .noDevice)
            return
        }
        guard force || target != device else { return }
        target = device
        referenceMonitor?.cancel()
        let attempt = UUID()
        revision = attempt
        processor.setReference(nil)
        status = .starting
        worker.start(device: device) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.revision == attempt else { return }
                switch result {
                case .success(let reference):
                    self.processor.setReference(reference)
                    self.monitor(reference)
                case .failure(let error):
                    self.status = .failed
                    self.logger.error("Playback reference unavailable: \(error, privacy: .public)")
                }
            }
        }
    }

    /// Reflects matching microphone and reference frames instead of reporting device startup as active processing.
    private func monitor(
        _ reference: PlaybackEchoReference
    ) {
        status = .waitingForReference
        referenceMonitor = Task { [weak self] in
            var previous = reference.processedPacketCount
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                let count = reference.processedPacketCount
                let updated: Status = count > previous ? .listening : .waitingForReference
                if self.status != updated { self.status = updated }
                previous = count
            }
        }
    }

    private func stop(
        status: Status
    ) {
        if target != nil {
            target = nil
            revision = UUID()
            processor.setReference(nil)
            referenceMonitor?.cancel()
            referenceMonitor = nil
            worker.stop()
        }
        if self.status != status { self.status = status }
    }
}

/// A short lock protects only reference replacement. PCM processing executes on the SDK microphone queue.
final class MicrophoneEchoProcessor: @unchecked Sendable {

    private struct State {
        var reference: PlaybackEchoReference?
        var calibration: UInt64 = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func setReference(
        _ reference: PlaybackEchoReference?
    ) {
        state.withLock { $0.reference = reference }
    }

    func invalidateCalibration() {
        state.withLock { $0.calibration &+= 1 }
    }

    func process(
        _ frame: RealtimeAudioFrame
    ) -> Data? {
        guard frame.sampleRate == FACENOW_ECHO_SAMPLE_RATE, frame.channels == 1,
            frame.samplesPerChannel == FACENOW_ECHO_FRAME_SAMPLES,
            frame.data.count == frame.samplesPerChannel * MemoryLayout<Int16>.stride,
            let snapshot = state.withLockIfAvailable({ $0 }),
            let reference = snapshot.reference
        else { return nil }
        let timestamp = CMTimeConvertScale(
            frame.presentationTimeStamp,
            timescale: 1_000_000,
            method: .roundHalfAwayFromZero
        )
        guard timestamp.isNumeric, timestamp.epoch == 0 else { return nil }
        return reference.process(
            frame.data,
            timestampUs: timestamp.value,
            calibration: snapshot.calibration
        )
    }
}

/// Retained by the tap callback and microphone queues until both are finished with it.
final class PlaybackEchoReference: @unchecked Sendable {

    let engine: OpaquePointer

    var processedPacketCount: UInt64 {
        FaceNowEchoCancellerProcessedPacketCount(engine)
    }

    init?() {
        guard let engine = FaceNowEchoCancellerCreate() else { return nil }
        self.engine = engine
    }

    deinit { FaceNowEchoCancellerDestroy(engine) }

    func process(
        _ pcm: Data,
        timestampUs: Int64,
        calibration: UInt64
    ) -> Data? {
        withUnsafeTemporaryAllocation(of: Int16.self, capacity: Int(FACENOW_ECHO_FRAME_SAMPLES)) { microphone in
            guard let input = microphone.baseAddress else { return nil }
            _ = pcm.copyBytes(to: UnsafeMutableRawBufferPointer(microphone))
            return withUnsafeTemporaryAllocation(
                of: Int16.self, capacity: Int(FACENOW_ECHO_FRAME_SAMPLES)
            ) { output in
                guard let result = output.baseAddress,
                    FaceNowEchoCancellerProcess(engine, input, timestampUs, calibration, result)
                else { return nil }
                return Data(bytes: result, count: pcm.count)
            }
        }
    }
}

/// Publishes control events off the UI and real-time audio queues.
private final class PlaybackEchoWorker: @unchecked Sendable {

    typealias RoutesListener = @Sendable ([EchoPlaybackDevice], AudioDeviceID, AudioDeviceID?) -> Void

    private let queue = DispatchQueue(label: "ai.xmax.FaceNow.EchoCancellation")
    private var routeListener: RoutesListener?
    private var routeBlock: AudioObjectPropertyListenerBlock?
    private var formatBlock: AudioObjectPropertyListenerBlock?
    private var observedDevice: AudioDeviceID = kAudioObjectUnknown
    private var tap: PlaybackReferenceTap?

    deinit {
        if let routeBlock {
            for selector in Self.routeSelectors {
                var address = Self.address(selector)
                AudioObjectRemovePropertyListenerBlock(Self.system, &address, queue, routeBlock)
            }
        }
        stopOnQueue()
    }

    private static let system = AudioObjectID(kAudioObjectSystemObject)
    private static let routeSelectors = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice]
    private static let formatSelectors = [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyStreams]

    func observeRoutes(
        _ listener: @escaping RoutesListener
    ) {
        queue.async { [self] in
            routeListener = listener
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.publishRoutes()
            }
            routeBlock = block
            for selector in Self.routeSelectors {
                var address = Self.address(selector)
                AudioObjectAddPropertyListenerBlock(Self.system, &address, queue, block)
            }
            publishRoutes()
        }
    }

    @available(macOS 14.2, *)
    func start(
        device: EchoPlaybackDevice,
        completion: @escaping @Sendable (Result<PlaybackEchoReference, PlaybackTapError>) -> Void
    ) {
        queue.async { [self] in
            stopOnQueue()
            do {
                let connected = try PlaybackReferenceTap(device: device)
                tap = connected
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                    self?.publishRoutes(invalidatedDevice: device.id)
                }
                formatBlock = block
                observedDevice = device.id
                for selector in Self.formatSelectors {
                    var address = Self.formatAddress(selector)
                    AudioObjectAddPropertyListenerBlock(device.id, &address, queue, block)
                }
                completion(.success(connected.reference))
            } catch let error as PlaybackTapError {
                completion(.failure(error))
            } catch {
                completion(.failure(PlaybackTapError(stage: "start playback tap", status: -1)))
            }
        }
    }

    func stop() {
        queue.async { [self] in stopOnQueue() }
    }

    private func stopOnQueue() {
        if let formatBlock {
            for selector in Self.formatSelectors {
                var address = Self.formatAddress(selector)
                AudioObjectRemovePropertyListenerBlock(observedDevice, &address, queue, formatBlock)
            }
        }
        formatBlock = nil
        observedDevice = kAudioObjectUnknown
        tap = nil
    }

    private func publishRoutes(
        invalidatedDevice: AudioDeviceID? = nil
    ) {
        let devices = Self.objectIDs(Self.system, selector: kAudioHardwarePropertyDevices)
            .compactMap { id -> EchoPlaybackDevice? in
                guard Self.number(id, selector: kAudioDevicePropertyDeviceIsAlive) != 0,
                    Self.number(id, selector: kAudioDevicePropertyIsHidden) == 0,
                    !Self.objectIDs(id, selector: kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput).isEmpty,
                    let uid = Self.string(id, selector: kAudioDevicePropertyDeviceUID),
                    let name = Self.string(id, selector: kAudioObjectPropertyName)
                else { return nil }
                return EchoPlaybackDevice(id: id, uid: uid, name: name)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        routeListener?(devices, Self.number(Self.system, selector: kAudioHardwarePropertyDefaultOutputDevice), invalidatedDevice)
    }

    private static func formatAddress(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        address(
            selector,
            scope: selector == kAudioDevicePropertyStreams ? kAudioDevicePropertyScopeOutput : kAudioObjectPropertyScopeGlobal
        )
    }

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func number(
        _ object: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> UInt32 {
        var address = address(selector)
        var value: UInt32 = 0
        var bytes = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &bytes, &value)
        return status == noErr ? value : 0
    }

    static func string(
        _ object: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var bytes = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &bytes, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func objectIDs(
        _ object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> [AudioObjectID] {
        var address = address(selector, scope: scope)
        var bytes: UInt32 = 0
        let size = UInt32(MemoryLayout<AudioObjectID>.stride)
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &bytes) == noErr, bytes >= size else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(bytes / size))
        let status = ids.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(object, &address, 0, nil, &bytes, $0.baseAddress!)
        }
        return status == noErr ? Array(ids.prefix(Int(bytes / size))) : []
    }
}

private struct PlaybackTapError: Error, CustomStringConvertible {

    let stage: String
    let status: OSStatus

    var description: String { "\(stage): \(status)" }

    static func check(
        _ status: OSStatus,
        stage: String
    ) throws {
        if status != noErr { throw Self(stage: stage, status: status) }
    }
}

/// A private, read-only tap. Its destruction always stops I/O before destroying the aggregate.
private final class PlaybackReferenceTap {

    let reference: PlaybackEchoReference

    private let ioQueue = DispatchQueue(label: "ai.xmax.FaceNow.EchoReferenceIO", qos: .userInitiated)
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var deviceID: AudioDeviceID = kAudioObjectUnknown
    private var callback: AudioDeviceIOProcID?
    private var running = false

    @available(macOS 14.2, *)
    init(
        device: EchoPlaybackDevice
    ) throws {
        guard let reference = PlaybackEchoReference() else {
            throw PlaybackTapError(stage: "allocate echo filter", status: -1)
        }
        self.reference = reference
        do {
            let description = CATapDescription(excludingProcesses: [], deviceUID: device.uid, stream: 0)
            description.name = "FaceNow Echo Cancellation"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            try PlaybackTapError.check(AudioHardwareCreateProcessTap(description, &tapID), stage: "create tap")

            var format = AudioStreamBasicDescription()
            var address = PlaybackEchoWorker.address(kAudioTapPropertyFormat)
            var bytes = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try PlaybackTapError.check(
                AudioObjectGetPropertyData(tapID, &address, 0, nil, &bytes, &format),
                stage: "query playback format"
            )
            guard format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 32,
                (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0,
                (format.mFormatFlags & kAudioFormatFlagIsBigEndian) == 0,
                format.mSampleRate.isFinite, (8000...384000).contains(format.mSampleRate)
            else { throw PlaybackTapError(stage: "unsupported playback format", status: -1) }
            let uid = PlaybackEchoWorker.string(tapID, selector: kAudioTapPropertyUID) ?? description.uuid.uuidString
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "FaceNow Echo Reference",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: uid, kAudioSubTapDriftCompensationKey: true]],
            ]
            try PlaybackTapError.check(
                AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID),
                stage: "create playback aggregate"
            )
            let rate = format.mSampleRate
            try PlaybackTapError.check(
                AudioDeviceCreateIOProcIDWithBlock(&callback, deviceID, ioQueue) { _, input, time, _, _ in
                    guard time.pointee.mFlags.contains(.hostTimeValid) else { return }
                    FaceNowEchoCancellerFeedPlayback(reference.engine, input, rate, time.pointee.mHostTime)
                },
                stage: "open playback stream"
            )
            guard let callback else { throw PlaybackTapError(stage: "register playback callback", status: -1) }
            try PlaybackTapError.check(AudioDeviceStart(deviceID, callback), stage: "start playback stream")
            running = true
        } catch {
            close()
            throw error
        }
    }

    deinit { close() }

    private func close() {
        if let callback {
            if running { AudioDeviceStop(deviceID, callback) }
            AudioDeviceDestroyIOProcID(deviceID, callback)
            self.callback = nil
        }
        if deviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(deviceID)
            deviceID = kAudioObjectUnknown
        }
        if #available(macOS 14.2, *), tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }
}
