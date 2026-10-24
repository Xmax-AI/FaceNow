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
@preconcurrency import AVFoundation
import Foundation
import os

/// Produces fixed-rate camera frames without queuing work on the SDK callback thread.
/// Transport state is confined to the worker queue; the frame scheduler alone crosses queues.
final class VirtualCameraOutput: @unchecked Sendable {
    /// The timestamped, bounded entry point for generated frames.
    let frames = ScheduledFrameStore()

    /// The serial transport queue and bounded renderer.
    private let worker = DispatchQueue(label: "ai.xmax.camera.output", qos: .userInitiated)
    private var renderer: VideoFrameRenderer?
    private var waitingBuffer: CVPixelBuffer?
    private var renderedInput: CVPixelBuffer?
    private var renderedOutput: CVPixelBuffer?

    /// The active CMIO sink and system-owned consumption queue.
    private var deviceID: CMIODeviceID = 0
    private var streamID: CMIOStreamID = 0
    private var bufferQueue: CMSimpleQueue?
    private var timer: DispatchSourceTimer?

    /// Periodic counters distinguish transport ticks from newly rendered video frames.
    private var statisticsStart: TimeInterval?
    private var sentFrames = 0
    private var sentNewFrames = 0
    private var passthroughFrames = 0
    private var convertedFrames = 0

    /// Test mode uses the same transport as generation.
    private var isTestPattern = false
    private let logger = Logger(subsystem: CameraConfiguration.appBundleID, category: "Output")

    private struct StartState {
        var id = UUID()
        var discovery: Task<VirtualCameraDiscovery.Sink, Error>?
    }
    private let startState = OSAllocatedUnfairLock(initialState: StartState())

    /// Waits for a usable sink and rejects late discovery results after stop or a newer start.
    func start(testPattern: Bool) async throws {
        let requestID = UUID()
        startState.withLock { state in
            state.discovery?.cancel()
            state = StartState(id: requestID)
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { throw OutputError.cameraAccessDenied }
        default:
            throw OutputError.cameraAccessDenied
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(12))
        defer {
            startState.withLock { state in
                if state.id == requestID { state.discovery = nil }
            }
        }
        while true {
            try Task.checkCancellation()
            guard startState.withLock({ $0.id == requestID }) else { throw CancellationError() }
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { throw VirtualCameraDiscovery.DiscoveryError.timedOut }
            let discovery = Task { try await VirtualCameraDiscovery.waitForSink(timeout: remaining) }
            startState.withLock { state in
                if state.id == requestID { state.discovery = discovery }
                else { discovery.cancel() }
            }
            do {
                try await withTaskCancellationHandler {
                    let sink = try await discovery.value
                    try Task.checkCancellation()
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        worker.async { [self] in
                            guard self.startState.withLock({ $0.id == requestID }), !discovery.isCancelled else {
                                continuation.resume(throwing: CancellationError())
                                return
                            }
                            do {
                                self.stopOnWorker()
                                let renderer = try VideoFrameRenderer()
                                self.renderer = renderer
                                self.waitingBuffer = try renderer.waiting()
                                let device = sink.device
                                let stream = sink.stream
                                var queue: Unmanaged<CMSimpleQueue>?
                                try Self.check(CMIOStreamCopyBufferQueue(stream, { _, _, _ in
                                    // A non-nil callback registers the queue; the timer handles producer pacing.
                                }, nil, &queue))
                                guard let queue else { throw OutputError.sinkUnavailable }
                                self.bufferQueue = queue.takeRetainedValue()
                                self.deviceID = device
                                self.streamID = stream
                                self.logger.notice("Starting virtual camera sink: camera authorization=\(AVCaptureDevice.authorizationStatus(for: .video).rawValue), device=\(device), stream=\(stream)")
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
                } onCancel: {
                    discovery.cancel()
                    self.worker.async {
                        if self.startState.withLock({ $0.id == requestID }) { self.stopOnWorker() }
                    }
                }
                try Task.checkCancellation()
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as RendererError {
                throw error
            } catch {
                // The device may be published before its sink accepts a producer connection.
                guard startState.withLock({ $0.id == requestID }) else { throw CancellationError() }
                if ContinuousClock.now >= deadline { throw VirtualCameraDiscovery.DiscoveryError.timedOut }
                try await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Stops production and releases queued samples after the system stops consuming.
    func stop() async {
        let stoppedID = UUID()
        startState.withLock { state in
            state.discovery?.cancel()
            state = StartState(id: stoppedID)
        }
        await withCheckedContinuation { continuation in
            worker.async {
                if self.startState.withLock({ $0.id == stoppedID }) { self.stopOnWorker() }
                continuation.resume()
            }
        }
    }

    /// Produces only when the sink queue has room; no waiting or frame accumulation.
    private func tick() {
        guard let renderer, let bufferQueue,
              CMSimpleQueueGetCount(bufferQueue) < min(2, CMSimpleQueueGetCapacity(bufferQueue)) else { return }
        let time = CMClockGetTime(CMClockGetHostTimeClock())
        do {
            let buffer: CVPixelBuffer
            var isNewFrame = false
            if isTestPattern {
                buffer = try renderer.testPattern(at: time.seconds)
                isNewFrame = true
            } else if let frame = frames.frame(now: time.seconds) {
                if renderedInput !== frame.pixelBuffer {
                    renderedOutput = try renderer.normalize(frame.pixelBuffer)
                    renderedInput = frame.pixelBuffer
                    isNewFrame = true
                }
                guard let renderedOutput else { return }
                buffer = renderedOutput
            } else if let waitingBuffer {
                renderedInput = nil
                renderedOutput = nil
                buffer = waitingBuffer
            } else {
                return
            }
            let sample = try renderer.sampleBuffer(buffer, at: time)
            let retained = Unmanaged.passRetained(sample)
            let status = CMSimpleQueueEnqueue(bufferQueue, element: retained.toOpaque())
            if status != noErr {
                retained.release()
                renderedInput = nil
            } else {
                recordOutput(at: time.seconds, isNewFrame: isNewFrame)
            }
        } catch {
            logger.error("Output frame dropped: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Logs measured delivery cadence without reading or retaining video contents.
    private func recordOutput(at time: TimeInterval, isNewFrame: Bool) {
        guard let statisticsStart else {
            self.statisticsStart = time
            return
        }
        sentFrames += 1
        if isNewFrame { sentNewFrames += 1 }
        if isNewFrame, !isTestPattern {
            if renderedInput === renderedOutput {
                passthroughFrames += 1
            } else {
                convertedFrames += 1
            }
        }
        let elapsed = time - statisticsStart
        guard elapsed >= 5 else { return }
        logger.notice("Virtual camera input: sent=\(Double(self.sentFrames) / elapsed) fps, new video frames=\(Double(self.sentNewFrames) / elapsed) fps, passthrough=\(self.passthroughFrames), converted=\(self.convertedFrames)")
        self.statisticsStart = time
        sentFrames = 0
        sentNewFrames = 0
        passthroughFrames = 0
        convertedFrames = 0
    }

    /// Runs exclusively on the output queue, never concurrently with an enqueue.
    private func stopOnWorker() {
        timer?.cancel()
        timer = nil
        if deviceID != 0, streamID != 0 {
            CMIODeviceStopStream(deviceID, streamID)
            var unusedQueue: Unmanaged<CMSimpleQueue>?
            CMIOStreamCopyBufferQueue(streamID, nil, nil, &unusedQueue)
            unusedQueue?.release()
        }
        if let bufferQueue {
            while let pointer = CMSimpleQueueDequeue(bufferQueue) {
                Unmanaged<CMSampleBuffer>.fromOpaque(pointer).release()
            }
        }
        bufferQueue = nil
        deviceID = 0
        streamID = 0
        renderedInput = nil
        renderedOutput = nil
        renderer = nil
        waitingBuffer = nil
        statisticsStart = nil
        sentFrames = 0
        sentNewFrames = 0
        passthroughFrames = 0
        convertedFrames = 0
        frames.reset(producer: nil)
    }

    /// Surfaces transport errors with their framework status code.
    private static func check(_ status: OSStatus) throws {
        if status != noErr { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

/// User-facing transport failures that can be resolved during setup.
enum OutputError: LocalizedError {
    case cameraAccessDenied
    case cameraUnavailable
    case sinkUnavailable

    /// Setup guidance for missing devices or producer streams.
    var errorDescription: String? {
        switch self {
        case .cameraAccessDenied: "Allow FaceNow in System Settings → Privacy & Security → Camera, then try again."
        case .cameraUnavailable: VirtualCameraDiscovery.DiscoveryError.timedOut.errorDescription
        case .sinkUnavailable: "The virtual camera input queue is not ready. Wait a moment and try again."
        }
    }
}
