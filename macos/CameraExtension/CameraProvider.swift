//
//  CameraProvider.swift
//  FaceNow
//

@preconcurrency import CoreMediaIO
import Foundation
import IOKit.audio
import IOSurface
import os

/// Owns the virtual device and serializes all extension work on the provider queue.
final class CameraProvider: NSObject, CMIOExtensionProviderSource {

    /// The provider exported to the system.
    private(set) var provider: CMIOExtensionProvider!

    /// The device persists for the entire provider lifetime.
    private var deviceSource: CameraDeviceSource!

    /// The provider's read-only metadata.
    var availableProperties: Set<CMIOExtensionProperty> { [.providerManufacturer] }

    /// Constructs the fixed device before starting the extension service.
    init(
        queue: DispatchQueue
    ) throws {
        super.init()
        provider = CMIOExtensionProvider(
            source: self,
            clientQueue: queue
        )
        deviceSource = try CameraDeviceSource(queue: queue)
        try provider.addDevice(deviceSource.device)
    }

    /// All signed camera consumers may connect; the sink separately restricts writers.
    func connect(
        to client: CMIOExtensionClient
    ) throws {}

    /// Drops frames when the producer exits without stopping its stream.
    func disconnect(
        from client: CMIOExtensionClient
    ) {
        deviceSource.disconnect(client)
    }

    /// Reports the camera manufacturer.
    func providerProperties(
        forProperties properties: Set<CMIOExtensionProperty>
    ) throws -> CMIOExtensionProviderProperties {
        let values = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) { values.manufacturer = "XMAX.AI" }
        return values
    }

    /// Provider metadata is read-only.
    func setProviderProperties(
        _ providerProperties: CMIOExtensionProviderProperties
    ) throws {}
}

/// Routes the paced host sink into the camera source using a bounded timestamped queue.
/// All mutable state is confined to the provider queue.
final class CameraDeviceSource: NSObject, CMIOExtensionDeviceSource, @unchecked Sendable {

    /// The device and its two independently controlled streams.
    private(set) var device: CMIOExtensionDevice!

    /// The consumer-facing stream exposing the negotiated camera formats.
    private var source: CameraStreamSource!

    /// The host-facing producer stream accepting generated frames.
    private var sink: CameraStreamSource!

    /// The shared serialization queue and reusable output renderer.
    private let queue: DispatchQueue

    /// The queue-confined renderer for the active source format.
    private var renderer: VideoFrameRenderer

    /// The cached offline artwork used when a producer is absent or its input expires.
    private var waitingBuffer: CVPixelBuffer

    /// Marks the first sample sent with a new source resolution.
    private var formatChanged = false

    /// The output clock runs while a producer or consumer is active.
    private var timer: DispatchSourceTimer?

    /// The active consumer count controlling whether the output clock is needed.
    private var consumerCount = 0

    /// Whether the current host has started supplying sink samples.
    private var producerIsRunning = false

    /// Only one authorized producer may own the sink.
    private var producerClient: CMIOExtensionClient?

    /// The identity rejecting queued samples from an earlier producer lifetime.
    private var producerToken = UUID()

    /// Whether a sink consume request is already waiting for completion.
    private var consumeIsPending = false

    /// The bounded host-time queue retaining samples for consumer delivery.
    private let frames = ScheduledFrameStore(
        usesHostTime: true,
        playoutDelay: 0,
        staleInterval: VirtualCameraConfiguration.staleInterval
    )

    /// The producer-cadence tick used to pace the negotiated consumer frame rate.
    private var outputTick = 0

    /// Five-second diagnostics compare sink input with frames submitted to CMIO consumers.
    private var statistics = TransportStatistics()

    /// The host-clock start of the current diagnostic reporting interval.
    private var statisticsStart: TimeInterval?

    /// The previous retained sink buffer used to distinguish repeated samples.
    private var previousConsumedBuffer: CVPixelBuffer?

    /// The previous delivered buffer used to measure actual output changes.
    private var previousSubmittedBuffer: CVPixelBuffer?

    /// The last host-clock submission time used to measure delivery gaps.
    private var previousSubmissionTime: TimeInterval?

    /// The logger records transport failures without logging frame contents.
    private let logger = Logger(
        subsystem: VirtualCameraConfiguration.extensionBundleID,
        category: "Camera"
    )

    /// The virtual transport and stable model identifier.
    var availableProperties: Set<CMIOExtensionProperty> { [.deviceTransportType, .deviceModel] }

    /// Creates source first so AVFoundation discovers the camera input stream.
    init(
        queue: DispatchQueue
    ) throws {
        self.queue = queue
        renderer = try VideoFrameRenderer(
            format: VirtualCameraConfiguration.videoFormat,
            waitingArtwork: VirtualCameraConfiguration.waitingArtwork
        )
        waitingBuffer = try renderer.waiting()
        super.init()
        device = CMIOExtensionDevice(
            localizedName: VirtualCameraConfiguration.deviceName,
            deviceID: VirtualCameraConfiguration.deviceID,
            legacyDeviceID: nil,
            source: self
        )
        let descriptions = [renderer.formatDescription] + (try VirtualCameraConfiguration.videoFormats.dropFirst().map {
            try VideoFrameRenderer(format: $0).formatDescription
        })
        let formats = descriptions.map { description in
            VirtualCameraConfiguration.sourceFrameRates.map { rate in
                let duration = CMTime(value: 1, timescale: Int32(rate))
                return CMIOExtensionStreamFormat(
                    formatDescription: description,
                    maxFrameDuration: duration,
                    minFrameDuration: duration,
                    validFrameDurations: nil
                )
            }
        }
        source = CameraStreamSource(
            device: self,
            direction: .source,
            formats: formats.flatMap { $0 }
        )
        sink = CameraStreamSource(
            device: self,
            direction: .sink,
            formats: formats.map { $0[0] }
        )
        try device.addStream(source.stream)
        try device.addStream(sink.stream)
    }

    /// Returns the device's read-only metadata.
    func deviceProperties(
        forProperties properties: Set<CMIOExtensionProperty>
    ) throws -> CMIOExtensionDeviceProperties {
        let values = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) { values.transportType = kIOAudioDeviceTransportTypeVirtual }
        if properties.contains(.deviceModel) { values.model = "FaceNow" }
        return values
    }

    /// The camera has no mutable device properties.
    func setDeviceProperties(
        _ deviceProperties: CMIOExtensionDeviceProperties
    ) throws {}

    /// Accepts consumer cadence changes while the producer owns the resolution.
    func selectFormat(
        _ index: Int,
        for direction: CMIOExtensionStream.Direction
    ) throws {
        if direction == .sink {
            guard !producerIsRunning || index == sink.activeFormatIndex else {
                throw CameraStreamSource.unsupportedFormat
            }
            sink.activateFormat(index, notify: false)
        } else {
            try selectSourceFormat(index, notify: false)
        }
    }

    /// Updates the waiting canvas before publishing a new consumer resolution.
    private func selectSourceFormat(
        _ index: Int,
        notify: Bool
    ) throws {
        if !CMFormatDescriptionEqual(
            source.formats[index].formatDescription,
            otherFormatDescription: source.activeFormat.formatDescription
        ) {
            guard !producerIsRunning else { throw CameraStreamSource.unsupportedFormat }
            let format = VirtualCameraConfiguration.videoFormats[index / VirtualCameraConfiguration.sourceFrameRates.count]
            let next = try VideoFrameRenderer(format: format, waitingArtwork: VirtualCameraConfiguration.waitingArtwork)
            let waiting = try next.waiting()
            renderer = next
            waitingBuffer = waiting
            formatChanged = true
        }
        source.activateFormat(index, notify: notify)
    }

    /// Allows one active local producer; DAL does not reliably expose its signing identity.
    func authorizeProducer(
        _ client: CMIOExtensionClient
    ) -> Bool {
        let allowed = !producerIsRunning || producerClient?.clientID == client.clientID
        logger.notice(
            "Sink authorization: signingID=\(client.signingID ?? "<nil>", privacy: .public), pid=\(client.pid), running=\(self.producerIsRunning), allowed=\(allowed)"
        )
        guard allowed else { return false }
        producerClient = client
        return true
    }

    /// Starts the selected stream without creating duplicate output timers.
    func start(
        direction: CMIOExtensionStream.Direction
    ) throws {
        resetStatistics()
        if direction == .source {
            consumerCount += 1
            logger.notice(
                "Camera consumer started: negotiated output=\(self.source.frameRate) fps, extension build=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown", privacy: .public)"
            )
        } else {
            guard producerClient != nil else { throw CameraExtensionError.noProducer }
            guard let index = source.formatIndex(for: sink.activeFormat.formatDescription, duration: source.frameDuration)
            else { throw CameraStreamSource.unsupportedFormat }
            try selectSourceFormat(index, notify: true)
            producerIsRunning = true
            producerToken = UUID()
            consumeIsPending = false
            frames.reset(producer: producerToken)
        }
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now(),
            repeating: 1 / Double(VirtualCameraConfiguration.frameRate),
            leeway: .milliseconds(1)
        )
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    /// Stops only the selected side, preserving other conference clients.
    func stop(
        direction: CMIOExtensionStream.Direction
    ) {
        resetStatistics()
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
    func disconnect(
        _ client: CMIOExtensionClient
    ) {
        guard producerClient?.clientID == client.clientID else { return }
        stop(direction: .sink)
    }

    /// Consumes at most one outstanding request and emits timestamped source frames.
    private func tick() {
        let time = CMClockGetTime(CMClockGetHostTimeClock())
        if statisticsStart == nil { statisticsStart = time.seconds }
        defer { reportStatistics(at: time.seconds) }
        if producerIsRunning, !consumeIsPending, let client = producerClient {
            consume(
                client: client,
                token: producerToken
            )
        }
        // Release superseded sink buffers even before a client opens the camera.
        // Otherwise this queue can retain the producer's entire bounded render pool.
        guard consumerCount > 0 else {
            _ = frames.frame(
                now: time.seconds,
                preferLatest: true
            )
            return
        }
        outputTick = (outputTick + 1) % VirtualCameraConfiguration.frameRate
        guard outputTick.isMultiple(of: VirtualCameraConfiguration.frameRate / source.frameRate) else { return }
        // The host has already paced interpolation frames; discard transport backlog after a late timer tick.
        let frame = frames.frame(
            now: time.seconds,
            preferLatest: true
        )
        let pixelBuffer = frame?.pixelBuffer ?? waitingBuffer
        do {
            let sample = try renderer.sampleBuffer(
                pixelBuffer,
                at: time,
                duration: source.frameDuration
            )
            source.stream.send(
                sample,
                discontinuity: formatChanged ? .unknown : [],
                hostTimeInNanoseconds: UInt64(time.seconds * 1_000_000_000)
            )
            formatChanged = false
            statistics.submitted += 1
            if let frame {
                if Self.isDifferentSurface(
                    pixelBuffer,
                    from: previousSubmittedBuffer
                ) {
                    statistics.newSubmitted += 1
                } else {
                    statistics.repeated += 1
                }
                previousSubmittedBuffer = pixelBuffer
                let age = max(0, time.seconds - frame.presentationTime)
                statistics.totalFrameAge += age
                statistics.maximumFrameAge = max(statistics.maximumFrameAge, age)
            } else {
                statistics.waiting += 1
                previousSubmittedBuffer = nil
            }
            if let previousSubmissionTime {
                let interval = time.seconds - previousSubmissionTime
                statistics.maximumSubmissionInterval = max(statistics.maximumSubmissionInterval, interval)
                if interval > source.frameDuration.seconds * 1.5 { statistics.lateSubmissions += 1 }
            }
            previousSubmissionTime = time.seconds
        } catch {
            statistics.sampleErrors += 1
            logger.error("Cannot create camera sample: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Defers completion processing to the provider queue and rejects stale callbacks.
    private func consume(
        client: CMIOExtensionClient,
        token: UUID
    ) {
        consumeIsPending = true
        sink.stream.consumeSampleBuffer(from: client) { [weak self] sample, sequence, _, hasMore, error in
            let result = ConsumedFrame(
                sample: sample,
                sequence: sequence,
                hasMore: hasMore,
                error: error
            )
            self?.queue.async { [weak self] in
                guard let self, self.producerIsRunning, self.producerToken == token else { return }
                self.consumeIsPending = false
                if let error = result.error {
                    self.statistics.consumeErrors += 1
                    self.logger.error("Sink consume failed: \(error.localizedDescription, privacy: .public)")
                }
                guard let sample = result.sample else {
                    self.statistics.emptyConsumes += 1
                    return
                }
                let dimensions = CMVideoFormatDescriptionGetDimensions(self.sink.activeFormat.formatDescription)
                guard let buffer = CMSampleBufferGetImageBuffer(sample),
                    CVPixelBufferGetWidth(buffer) == Int(dimensions.width),
                    CVPixelBufferGetHeight(buffer) == Int(dimensions.height),
                    CVPixelBufferGetPixelFormatType(buffer) == VirtualCameraConfiguration.pixelFormat
                else {
                    self.statistics.invalidSamples += 1
                    return
                }
                let time = CMClockGetTime(CMClockGetHostTimeClock())
                self.statistics.received += 1
                if Self.isDifferentSurface(
                    buffer,
                    from: self.previousConsumedBuffer
                ) {
                    self.statistics.newReceived += 1
                }
                self.previousConsumedBuffer = buffer
                self.frames.submit(
                    buffer,
                    producer: token,
                    timestamp: CMSampleBufferGetPresentationTimeStamp(sample).seconds,
                    now: time.seconds
                )
                self.sink.stream.notifyScheduledOutputChanged(
                    CMIOExtensionScheduledOutput(
                        sequenceNumber: result.sequence,
                        hostTimeInNanoseconds: UInt64(time.seconds * 1_000_000_000)
                    )
                )
                if result.hasMore {
                    self.consume(
                        client: client,
                        token: token
                    )
                }
            }
        }
    }

    /// Uses shared IOSurface identity because CMIO can wrap the same pixels in different CVPixelBuffer objects.
    private static func isDifferentSurface(
        _ buffer: CVPixelBuffer,
        from previous: CVPixelBuffer?
    ) -> Bool {
        guard let previous else { return true }
        guard let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue(),
            let previousSurface = CVPixelBufferGetIOSurface(previous)?.takeUnretainedValue()
        else {
            return buffer !== previous
        }
        return IOSurfaceGetID(surface) != IOSurfaceGetID(previousSurface)
    }

    /// Starts a fresh measurement when producer or consumer ownership changes.
    private func resetStatistics() {
        statistics = TransportStatistics()
        statisticsStart = nil
        previousConsumedBuffer = nil
        previousSubmittedBuffer = nil
        previousSubmissionTime = nil
        _ = frames.takeStatistics()
    }

    /// Reports submission rates, not the conference application's display or encoding rate.
    private func reportStatistics(
        at time: TimeInterval
    ) {
        guard let statisticsStart else { return }
        let elapsed = time - statisticsStart
        guard elapsed >= 5 else { return }
        let values = statistics
        let drops = frames.takeStatistics()
        let videoCount = values.submitted - values.waiting
        let averageAge = videoCount > 0 ? values.totalFrameAge / Double(videoCount) : 0
        logger.notice(
            "Extension frame rates: window=\(elapsed)s, consumers=\(self.consumerCount), negotiated=\(self.source.frameRate) fps, received=\(Double(values.received) / elapsed) fps, received new buffers=\(Double(values.newReceived) / elapsed) fps, submitted=\(Double(values.submitted) / elapsed) fps, submitted new buffers=\(Double(values.newSubmitted) / elapsed) fps, repeated=\(Double(values.repeated) / elapsed) fps, waiting=\(values.waiting)"
        )
        logger.notice(
            "Extension queue: superseded samples=\(drops.superseded), expired=\(drops.expired), overflow=\(drops.overflow), discontinuity=\(drops.discontinuity), pending=\(self.frames.pendingFrameCount), frame age avg=\(averageAge * 1000)ms max=\(values.maximumFrameAge * 1000)ms, output gap max=\(values.maximumSubmissionInterval * 1000)ms, late submissions=\(values.lateSubmissions), consume errors=\(values.consumeErrors), empty consumes=\(values.emptyConsumes), invalid samples=\(values.invalidSamples), sample errors=\(values.sampleErrors)"
        )
        statistics = TransportStatistics()
        self.statisticsStart = time
    }
}

/// Counts transport events without copying pixels or adding per-frame log messages.
private struct TransportStatistics {

    /// The number of valid sink samples received during the reporting interval.
    var received = 0

    /// The number of received buffers distinct from the preceding input buffer.
    var newReceived = 0

    /// The number of samples submitted to the consumer-facing stream.
    var submitted = 0

    /// The number of submitted buffers distinct from the preceding output buffer.
    var newSubmitted = 0

    /// The number of output submissions reusing the preceding displayed buffer.
    var repeated = 0

    /// The number of output submissions using the neutral waiting frame.
    var waiting = 0

    /// The number of submissions whose delivery interval exceeded the expected cadence.
    var lateSubmissions = 0

    /// The number of sink consume completions reporting a framework error.
    var consumeErrors = 0

    /// The number of consume completions without a sample or an error.
    var emptyConsumes = 0

    /// The number of samples rejected because their media representation is incompatible.
    var invalidSamples = 0

    /// The number of output sample creation or submission failures.
    var sampleErrors = 0

    /// The accumulated input-to-output frame age in seconds.
    var totalFrameAge: TimeInterval = 0

    /// The maximum observed input-to-output frame age in seconds.
    var maximumFrameAge: TimeInterval = 0

    /// The maximum observed gap between consumer submissions in seconds.
    var maximumSubmissionInterval: TimeInterval = 0
}

/// Retains a consumed buffer while moving the completion onto the provider queue.
private struct ConsumedFrame: @unchecked Sendable {

    /// The consumed sample retained until the provider queue processes this result.
    let sample: CMSampleBuffer?

    /// The sink sequence number returned with this consume completion.
    let sequence: UInt64

    /// Whether CMIO reports additional sink samples available for consumption.
    let hasMore: Bool

    /// The framework failure returned with this consume completion, when present.
    let error: Error?
}

/// The producer stream was started without an authorized host.
private enum CameraExtensionError: Error {

    /// The sink was started without a currently accepted producer client.
    case noProducer
}
