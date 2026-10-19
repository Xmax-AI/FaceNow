//
//  VirtualCameraOutput.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import CoreMediaIO
import Foundation
import os

/// Produces fixed-rate camera frames without queuing work on the SDK callback thread.
/// Transport state is confined to the worker queue; the mailbox alone crosses queues.
final class VirtualCameraOutput: @unchecked Sendable {
    /// The fast single-slot entry point for generated frames.
    let frames = LatestFrameStore()

    /// The serial transport queue and bounded renderer.
    private let worker = DispatchQueue(label: "ai.xmax.camera.output", qos: .userInitiated)
    private var renderer: VideoFrameRenderer?
    private var waitingBuffer: CVPixelBuffer?

    /// The active CMIO sink and system-owned consumption queue.
    private var deviceID: CMIODeviceID = 0
    private var streamID: CMIOStreamID = 0
    private var bufferQueue: CMSimpleQueue?
    private var timer: DispatchSourceTimer?

    /// Test mode uses the same transport as generation.
    private var isTestPattern = false
    private let logger = Logger(subsystem: CameraConfiguration.appBundleID, category: "Output")

    /// Opens the installed sink or returns an actionable setup error.
    func start(testPattern: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            worker.async { [self] in
                do {
                    self.stopOnWorker()
                    let renderer = try VideoFrameRenderer()
                    self.renderer = renderer
                    self.waitingBuffer = try renderer.waiting()
                    let device = try Self.findDevice()
                    let streams = try Self.objectIDs(
                        device, selector: UInt32(kCMIODevicePropertyStreams), scope: UInt32(kCMIODevicePropertyScopeOutput)
                    )
                    guard let stream = try streams.first(where: {
                        try Self.uint32($0, selector: UInt32(kCMIOStreamPropertyDirection)) == 0
                    }) else { throw OutputError.sinkUnavailable }
                    var queue: Unmanaged<CMSimpleQueue>?
                    try Self.check(CMIOStreamCopyBufferQueue(stream, nil, nil, &queue))
                    guard let queue else { throw OutputError.sinkUnavailable }
                    self.bufferQueue = queue.takeRetainedValue()
                    self.deviceID = device
                    self.streamID = stream
                    try Self.check(CMIODeviceStartStream(device, stream))
                    self.isTestPattern = testPattern
                    let timer = DispatchSource.makeTimerSource(queue: self.worker)
                    timer.schedule(deadline: .now(), repeating: 1 / Double(CameraConfiguration.frameRate), leeway: .milliseconds(1))
                    timer.setEventHandler { [weak self] in self?.tick() }
                    self.timer = timer
                    timer.resume()
                    continuation.resume()
                } catch {
                    self.stopOnWorker()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Stops production and releases queued samples after the system stops consuming.
    func stop() async {
        await withCheckedContinuation { continuation in
            worker.async {
                self.stopOnWorker()
                continuation.resume()
            }
        }
    }

    /// Produces only when the sink queue has room; no waiting or frame accumulation.
    private func tick() {
        guard let renderer, let bufferQueue,
              CMSimpleQueueGetCount(bufferQueue) < CMSimpleQueueGetCapacity(bufferQueue) else { return }
        let time = CMClockGetTime(CMClockGetHostTimeClock())
        do {
            let buffer: CVPixelBuffer
            if isTestPattern {
                buffer = try renderer.testPattern(at: time.seconds)
            } else if let frame = frames.latest(now: time.seconds) {
                buffer = try renderer.normalize(frame.pixelBuffer)
            } else if let waitingBuffer {
                buffer = waitingBuffer
            } else {
                return
            }
            let sample = try renderer.sampleBuffer(buffer, at: time)
            let retained = Unmanaged.passRetained(sample)
            let status = CMSimpleQueueEnqueue(bufferQueue, element: retained.toOpaque())
            if status != noErr { retained.release() }
        } catch {
            logger.error("Output frame dropped: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Runs exclusively on the output queue, never concurrently with an enqueue.
    private func stopOnWorker() {
        timer?.cancel()
        timer = nil
        if deviceID != 0, streamID != 0 { CMIODeviceStopStream(deviceID, streamID) }
        if let bufferQueue {
            while let pointer = CMSimpleQueueDequeue(bufferQueue) {
                Unmanaged<CMSampleBuffer>.fromOpaque(pointer).release()
            }
        }
        bufferQueue = nil
        deviceID = 0
        streamID = 0
        renderer = nil
        waitingBuffer = nil
        frames.reset(producer: nil)
    }

    /// Locates the stable device UID instead of relying on localized display names.
    private static func findDevice() throws -> CMIODeviceID {
        var address = CMIOObjectPropertyAddress(mSelector: UInt32(kCMIOHardwarePropertyAllowScreenCaptureDevices),
                                              mScope: UInt32(kCMIOObjectPropertyScopeGlobal), mElement: UInt32(kCMIOObjectPropertyElementMain))
        var allow: UInt32 = 1
        try check(CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, 4, &allow))
        for device in try objectIDs(CMIOObjectID(kCMIOObjectSystemObject), selector: UInt32(kCMIOHardwarePropertyDevices)) {
            var uidAddress = CMIOObjectPropertyAddress(mSelector: UInt32(kCMIODevicePropertyDeviceUID),
                                                     mScope: UInt32(kCMIOObjectPropertyScopeGlobal), mElement: UInt32(kCMIOObjectPropertyElementMain))
            var value: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<CFString>.size)
            let status = CMIOObjectGetPropertyData(device, &uidAddress, 0, nil, size, &size, &value)
            if status == noErr, let uid = value?.takeRetainedValue(),
               (uid as String).caseInsensitiveCompare(CameraConfiguration.deviceID.uuidString) == .orderedSame {
                return device
            }
        }
        throw OutputError.cameraUnavailable
    }

    /// Reads an array of CMIO objects using the property's actual byte size.
    private static func objectIDs(
        _ object: CMIOObjectID,
        selector: CMIOObjectPropertySelector,
        scope: CMIOObjectPropertyScope = UInt32(kCMIOObjectPropertyScopeGlobal)
    ) throws -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(mSelector: selector, mScope: scope,
                                              mElement: UInt32(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        try check(CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &size))
        var values = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        guard !values.isEmpty else { return [] }
        let status = values.withUnsafeMutableBytes {
            CMIOObjectGetPropertyData(object, &address, 0, nil, size, &size, $0.baseAddress!)
        }
        try check(status)
        return Array(values.prefix(Int(size) / MemoryLayout<CMIOObjectID>.size))
    }

    /// Reads a scalar stream property.
    private static func uint32(_ object: CMIOObjectID, selector: CMIOObjectPropertySelector) throws -> UInt32 {
        var address = CMIOObjectPropertyAddress(mSelector: selector, mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
                                              mElement: UInt32(kCMIOObjectPropertyElementMain))
        var value: UInt32 = 0
        var size: UInt32 = 4
        try check(CMIOObjectGetPropertyData(object, &address, 0, nil, size, &size, &value))
        return value
    }

    /// Surfaces transport errors with their framework status code.
    private static func check(_ status: OSStatus) throws {
        if status != noErr { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

/// User-facing transport failures that can be resolved during setup.
enum OutputError: LocalizedError {
    case cameraUnavailable
    case sinkUnavailable

    /// Setup guidance for missing devices or producer streams.
    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: "Xmax Virtual Camera is unavailable. Install and enable the camera extension first."
        case .sinkUnavailable: "The camera input stream is unavailable. Quit other Xmax Camera instances and try again."
        }
    }
}
