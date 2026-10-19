//
//  CameraProvider.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import CoreMediaIO
import Foundation
import IOKit.audio
import os

/// Owns the virtual device and serializes all extension work on the provider queue.
final class CameraProvider: NSObject, CMIOExtensionProviderSource {
    /// The provider exported to the system.
    private(set) var provider: CMIOExtensionProvider!

    /// The device persists for the entire provider lifetime.
    private var deviceSource: CameraDeviceSource!

    /// Constructs the fixed device before starting the extension service.
    init(queue: DispatchQueue) throws {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: queue)
        deviceSource = try CameraDeviceSource(queue: queue)
        try provider.addDevice(deviceSource.device)
    }

    /// All signed camera consumers may connect; the sink separately restricts writers.
    func connect(to client: CMIOExtensionClient) throws {}

    /// Drops frames when the producer exits without stopping its stream.
    func disconnect(from client: CMIOExtensionClient) {
        deviceSource.disconnect(client)
    }

    /// The provider's read-only metadata.
    var availableProperties: Set<CMIOExtensionProperty> { [.providerManufacturer] }

    /// Reports the camera manufacturer.
    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let values = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) { values.manufacturer = "XMAX.AI" }
        return values
    }

    /// Provider metadata is read-only.
    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}

/// Routes the paced host sink into the camera source using a bounded timestamped queue.
/// All mutable state is confined to the provider queue.
final class CameraDeviceSource: NSObject, CMIOExtensionDeviceSource, @unchecked Sendable {
    /// The device and its two independently controlled streams.
    private(set) var device: CMIOExtensionDevice!
    private var source: CameraStreamSource!
    private var sink: CameraStreamSource!

    /// The shared serialization queue and reusable output renderer.
    private let queue: DispatchQueue
    private let renderer: VideoFrameRenderer
    private let waitingBuffer: CVPixelBuffer

    /// The output clock runs while a producer or consumer is active.
    private var timer: DispatchSourceTimer?
    private var consumerCount = 0
    private var producerIsRunning = false

    /// Only one authorized producer may own the sink.
    private var producerClient: CMIOExtensionClient?
    private var producerToken = UUID()
    private var consumeIsPending = false
    private let frames = ScheduledFrameStore(usesHostTime: true, playoutDelay: 0)
    private var outputTick = 0

    /// The logger records transport failures without logging frame contents.
    private let logger = Logger(subsystem: CameraConfiguration.extensionBundleID, category: "Camera")

    /// Creates source first so AVFoundation discovers the camera input stream.
    init(queue: DispatchQueue) throws {
        self.queue = queue
        renderer = try VideoFrameRenderer()
        waitingBuffer = try renderer.waiting()
        super.init()
        device = CMIOExtensionDevice(localizedName: CameraConfiguration.deviceName,
                                     deviceID: CameraConfiguration.deviceID, legacyDeviceID: nil, source: self)
        let formats = CameraConfiguration.sourceFrameRates.map { rate in
            let duration = CMTime(value: 1, timescale: Int32(rate))
            return CMIOExtensionStreamFormat(
                formatDescription: renderer.formatDescription,
                maxFrameDuration: duration, minFrameDuration: duration, validFrameDurations: nil
            )
        }
        source = CameraStreamSource(device: self, direction: .source, formats: formats)
        sink = CameraStreamSource(device: self, direction: .sink, formats: [formats[0]])
        try device.addStream(source.stream)
        try device.addStream(sink.stream)
    }

    /// The virtual transport and stable model identifier.
    var availableProperties: Set<CMIOExtensionProperty> { [.deviceTransportType, .deviceModel] }

    /// Returns the device's read-only metadata.
    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let values = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) { values.transportType = kIOAudioDeviceTransportTypeVirtual }
        if properties.contains(.deviceModel) { values.model = "Xmax Camera" }
        return values
    }

    /// The camera has no mutable device properties.
    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    /// Allows one active local producer; DAL does not reliably expose its signing identity.
    func authorizeProducer(_ client: CMIOExtensionClient) -> Bool {
        let allowed = !producerIsRunning || producerClient?.clientID == client.clientID
        logger.notice("Sink authorization: signingID=\(client.signingID ?? "<nil>", privacy: .public), pid=\(client.pid), running=\(self.producerIsRunning), allowed=\(allowed)")
        guard allowed else { return false }
        producerClient = client
        return true
    }

    /// Starts the selected stream without creating duplicate output timers.
    func start(direction: CMIOExtensionStream.Direction) throws {
        if direction == .source {
            consumerCount += 1
        } else {
            guard producerClient != nil else { throw CameraExtensionError.noProducer }
            producerIsRunning = true
            producerToken = UUID()
            consumeIsPending = false
            frames.reset(producer: producerToken)
        }
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1 / Double(CameraConfiguration.frameRate), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    /// Stops only the selected side, preserving other conference clients.
    func stop(direction: CMIOExtensionStream.Direction) {
        if direction == .source {
            consumerCount = max(0, consumerCount - 1)
        } else {
            producerIsRunning = false
            producerClient = nil
            producerToken = UUID()
            consumeIsPending = false
            frames.reset(producer: nil)
        }
        if consumerCount == 0 && !producerIsRunning {
            timer?.cancel()
            timer = nil
        }
    }

    /// Handles producer crashes and normal disconnects identically.
    func disconnect(_ client: CMIOExtensionClient) {
        guard producerClient?.clientID == client.clientID else { return }
        stop(direction: .sink)
    }

    /// Consumes at most one outstanding request and emits timestamped source frames.
    private func tick() {
        if producerIsRunning, !consumeIsPending, let client = producerClient {
            consume(client: client, token: producerToken)
        }
        guard consumerCount > 0 else { return }
        outputTick = (outputTick + 1) % CameraConfiguration.frameRate
        guard outputTick.isMultiple(of: CameraConfiguration.frameRate / source.frameRate) else { return }
        let time = CMClockGetTime(CMClockGetHostTimeClock())
        let pixelBuffer = frames.frame(now: time.seconds, preferLatest: source.frameRate < CameraConfiguration.frameRate)?.pixelBuffer ?? waitingBuffer
        do {
            let sample = try renderer.sampleBuffer(pixelBuffer, at: time, duration: source.frameDuration)
            source.stream.send(sample, discontinuity: [], hostTimeInNanoseconds: UInt64(time.seconds * 1_000_000_000))
        } catch {
            logger.error("Cannot create camera sample: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Defers completion processing to the provider queue and rejects stale callbacks.
    private func consume(client: CMIOExtensionClient, token: UUID) {
        consumeIsPending = true
        sink.stream.consumeSampleBuffer(from: client) { [weak self] sample, sequence, _, hasMore, error in
            let result = ConsumedFrame(sample: sample, sequence: sequence, hasMore: hasMore, error: error)
            self?.queue.async { [weak self] in
                guard let self, self.producerIsRunning, self.producerToken == token else { return }
                self.consumeIsPending = false
                if let error = result.error {
                    self.logger.error("Sink consume failed: \(error.localizedDescription, privacy: .public)")
                }
                guard let sample = result.sample, let buffer = CMSampleBufferGetImageBuffer(sample),
                      CVPixelBufferGetWidth(buffer) == CameraConfiguration.width,
                      CVPixelBufferGetHeight(buffer) == CameraConfiguration.height,
                      CVPixelBufferGetPixelFormatType(buffer) == CameraConfiguration.pixelFormat else { return }
                let time = CMClockGetTime(CMClockGetHostTimeClock())
                self.frames.submit(buffer, producer: token, timestamp: CMSampleBufferGetPresentationTimeStamp(sample).seconds, now: time.seconds)
                self.sink.stream.notifyScheduledOutputChanged(CMIOExtensionScheduledOutput(
                    sequenceNumber: result.sequence, hostTimeInNanoseconds: UInt64(time.seconds * 1_000_000_000)
                ))
                if result.hasMore { self.consume(client: client, token: token) }
            }
        }
    }
}

/// Retains a consumed buffer while moving the completion onto the provider queue.
private struct ConsumedFrame: @unchecked Sendable {
    let sample: CMSampleBuffer?
    let sequence: UInt64
    let hasMore: Bool
    let error: Error?
}

/// The producer stream was started without an authorized host.
private enum CameraExtensionError: Error {
    case noProducer
}
