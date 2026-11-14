//
//  ScheduledFrameStore.swift
//  FaceNow
//

import CoreVideo
import Foundation

/// Retains an immutable frame until its host-clock presentation time.
struct ScheduledVideoFrame: @unchecked Sendable {

    /// The retained input pixels, which callers must not mutate while queued or displayed.
    let pixelBuffer: CVPixelBuffer

    /// The host-clock receive time in seconds used to bound retained frame age.
    let receivedAt: TimeInterval

    /// The host-clock deadline in seconds at which this frame becomes eligible for display.
    let presentationTime: TimeInterval
}

/// Counts discarded transport samples separately from repeated output frames.
struct FrameQueueStatistics {

    /// The number of pending samples discarded because the queue reached capacity.
    var overflow = 0

    /// The number of queued samples discarded because their age or latency exceeded the bound.
    var expired = 0

    /// The number of due samples replaced by a newer due sample.
    var superseded = 0

    /// The number of source-timeline resets detected during submission.
    var discontinuity = 0
}

/// Preserves interpolation bursts in a bounded queue without blocking SDK delivery.
final class ScheduledFrameStore: @unchecked Sendable {

    /// The timeline mode and maximum pending work.
    private let usesHostTime: Bool

    /// The receive-to-playout delay in seconds applied to rebased SDK timestamps.
    private let playoutDelay: TimeInterval

    /// The maximum number of pending presentation slots retained by one producer.
    private let capacity: Int

    /// The caller's maximum additional video hold, in seconds.
    private let maximumVideoDelay: TimeInterval

    /// Owns queued pixels when long waits would otherwise retain a producer's scarce pool leases.
    private let copiesFrames: Bool

    /// The manual video hold, kept separate from the base clock shared with audio.
    private var videoDelay: TimeInterval = 0

    /// Drops elapsed slots once when reducing the video hold instead of replaying the backlog.
    private var catchesUp = false

    /// The maximum allowed presentation lateness in seconds for a queued frame.
    private let maximumLatency: TimeInterval = 0.15

    /// The caller-selected maximum age of a retained input frame, in seconds.
    private let staleInterval: TimeInterval

    /// The lock protects producer ownership, timeline mapping and retained frames.
    private let lock = NSLock()

    /// The lifecycle identity allowed to submit retained samples, protected by the lock.
    private var producer: UUID?

    /// The bounded presentation queue, protected by the lock.
    private var pending: [ScheduledVideoFrame] = []

    /// The retained current frame, reused only while it remains fresh.
    private var displayed: ScheduledVideoFrame?

    /// The initial source timestamp in seconds used for host-clock rebasing.
    private var sourceOrigin: TimeInterval?

    /// The corresponding host-clock origin in seconds for source rebasing.
    private var hostOrigin: TimeInterval?

    /// The previous source timestamp used to detect backward jumps or large gaps.
    private var lastTimestamp: TimeInterval?

    /// The actual deadline paired with the last source timestamp for synchronized audio.
    private var lastPresentationTime: TimeInterval?

    /// The next host-clock presentation slot reserved for an interpolation burst.
    private var nextPresentationTime: TimeInterval?

    /// The queue discard counters read and reset under the same state lock.
    private var statistics = FrameQueueStatistics()

    /// Reports retained work for diagnostics without exposing queue mutation.
    var pendingFrameCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }

    /// SDK timestamps are rebased once; CMIO input already uses the host clock.
    init(
        usesHostTime: Bool = false,
        playoutDelay: TimeInterval = 1.0 / 30,
        staleInterval: TimeInterval = 2,
        capacity: Int = 8,
        maximumVideoDelay: TimeInterval = 0,
        copiesFrames: Bool = false
    ) {
        self.usesHostTime = usesHostTime
        self.playoutDelay = playoutDelay
        self.staleInterval = staleInterval
        self.capacity = max(1, capacity)
        self.maximumVideoDelay = maximumVideoDelay.isFinite ? max(0, maximumVideoDelay) : 0
        self.copiesFrames = copiesFrames
    }

    /// A new producer invalidates every queued frame and the previous timeline.
    func reset(
        producer: UUID?,
        videoDelay: TimeInterval = 0
    ) {
        lock.lock()
        defer { lock.unlock() }
        self.producer = producer
        self.videoDelay = boundedVideoDelay(videoDelay)
        catchesUp = false
        clearTimeline()
        displayed = nil
        statistics = FrameQueueStatistics()
    }

    /// Changes output timing without rebasing the audio clock or accepting a stale session's setting.
    func setVideoDelay(
        _ delay: TimeInterval,
        producer: UUID
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard self.producer == producer else { return }
        let value = boundedVideoDelay(delay)
        if value < videoDelay { catchesUp = true }
        videoDelay = value
    }

    /// Retains frames in timestamp order, rebasing interrupted or discontinuous timelines.
    func submit(
        _ pixelBuffer: CVPixelBuffer,
        producer: UUID,
        timestamp: TimeInterval,
        duration: TimeInterval? = nil,
        now: TimeInterval
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard self.producer == producer, now.isFinite else { return }
        let timestamp = timestamp.isFinite ? timestamp : (lastTimestamp.map { $0 + 1.0 / 60 } ?? now)
        if let lastTimestamp {
            if timestamp == lastTimestamp { return }
            if timestamp < lastTimestamp || timestamp - lastTimestamp > staleInterval {
                statistics.discontinuity += pending.count
                clearTimeline()
            }
        }
        if sourceOrigin == nil {
            sourceOrigin = timestamp
            hostOrigin = now + playoutDelay
        }
        var due = usesHostTime ? timestamp + playoutDelay : hostOrigin! + timestamp - sourceOrigin!
        if !usesHostTime, let duration, duration.isFinite, duration > 0, duration < 1 {
            // Match the SDK preview: late bursts start a new display interval instead of catching up in a burst.
            due = max(nextPresentationTime ?? now + playoutDelay, now + playoutDelay)
        }
        if !usesHostTime, abs(due - now) > maximumLatency {
            statistics.discontinuity += pending.count
            clearTimeline()
            sourceOrigin = timestamp
            hostOrigin = now + playoutDelay
            due = hostOrigin!
        }
        if !usesHostTime, let duration, duration.isFinite, duration > 0, duration < 1 {
            nextPresentationTime = due + duration
        }
        lastTimestamp = timestamp
        lastPresentationTime = due
        guard let retainedPixels = copiesFrames ? copyPixels(pixelBuffer) : pixelBuffer else {
            statistics.overflow += 1
            return
        }
        pending.append(
            ScheduledVideoFrame(
                pixelBuffer: retainedPixels,
                receivedAt: now,
                presentationTime: due
            )
        )
        if pending.count > capacity {
            let count = pending.count - capacity
            statistics.overflow += count
            pending.removeFirst(count)
        }
    }

    /// Maps audio onto the automatic playout interval, before the independent manual video hold.
    /// Returns nil before video starts, after producer replacement, or across a stale timeline.
    func presentationTime(
        forSourceTimestamp timestamp: TimeInterval,
        producer: UUID
    ) -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        guard self.producer == producer, timestamp.isFinite,
            let lastTimestamp, let lastPresentationTime,
            abs(timestamp - lastTimestamp) < maximumLatency
        else { return nil }
        return lastPresentationTime + timestamp - lastTimestamp
    }

    /// Presents due frames in order; lower-rate consumers may skip to the latest due frame.
    func frame(
        now: TimeInterval,
        preferLatest: Bool = false
    ) -> ScheduledVideoFrame? {
        lock.lock()
        defer { lock.unlock() }
        let previousCount = pending.count
        pending.removeAll {
            now - $0.receivedAt >= staleInterval + videoDelay
                || now - $0.presentationTime - videoDelay > maximumLatency
        }
        statistics.expired += previousCount - pending.count
        var selectedCount = 0
        while let first = pending.first, first.presentationTime + videoDelay <= now + 0.0005 {
            displayed = pending.removeFirst()
            selectedCount += 1
            if !preferLatest && !catchesUp { break }
        }
        if selectedCount > 0 { catchesUp = false }
        statistics.superseded += max(0, selectedCount - 1)
        guard let displayed, now >= displayed.receivedAt,
            now - displayed.receivedAt < staleInterval + videoDelay
        else {
            self.displayed = nil
            return nil
        }
        return ScheduledVideoFrame(
            pixelBuffer: displayed.pixelBuffer,
            receivedAt: displayed.receivedAt,
            presentationTime: displayed.presentationTime + videoDelay
        )
    }

    /// Drains interval counters without changing queued frames or their presentation times.
    func takeStatistics() -> FrameQueueStatistics {
        lock.lock()
        defer { lock.unlock() }
        let result = statistics
        statistics = FrameQueueStatistics()
        return result
    }

    /// Rejects invalid delays while preserving the configured queue's maximum hold.
    private func boundedVideoDelay(
        _ delay: TimeInterval
    ) -> TimeInterval {
        delay.isFinite ? min(maximumVideoDelay, max(0, delay)) : 0
    }

    /// Copies immutable pixels and propagating metadata without retaining external native-resource leases.
    private func copyPixels(
        _ source: CVPixelBuffer
    ) -> CVPixelBuffer? {
        var result: CVPixelBuffer?
        guard
            CVPixelBufferCreate(
                nil,
                CVPixelBufferGetWidth(source),
                CVPixelBufferGetHeight(source),
                CVPixelBufferGetPixelFormatType(source),
                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
                &result
            ) == kCVReturnSuccess, let result
        else { return nil }
        guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        guard CVPixelBufferLockBaseAddress(result, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(result, []) }
        let planeCount = CVPixelBufferGetPlaneCount(source)
        guard planeCount == CVPixelBufferGetPlaneCount(result) else { return nil }
        for plane in 0..<max(1, planeCount) {
            let planar = planeCount > 0
            let input = planar ? CVPixelBufferGetBaseAddressOfPlane(source, plane) : CVPixelBufferGetBaseAddress(source)
            let output =
                planar ? CVPixelBufferGetBaseAddressOfPlane(result, plane) : CVPixelBufferGetBaseAddress(result)
            guard let input, let output else { return nil }
            let inputStride =
                planar
                ? CVPixelBufferGetBytesPerRowOfPlane(source, plane) : CVPixelBufferGetBytesPerRow(source)
            let outputStride =
                planar
                ? CVPixelBufferGetBytesPerRowOfPlane(result, plane) : CVPixelBufferGetBytesPerRow(result)
            let height = planar ? CVPixelBufferGetHeightOfPlane(source, plane) : CVPixelBufferGetHeight(source)
            for row in 0..<height {
                memcpy(
                    output.advanced(by: row * outputStride),
                    input.advanced(by: row * inputStride),
                    min(inputStride, outputStride)
                )
            }
        }
        CVBufferPropagateAttachments(source, result)
        return result
    }

    /// Rebases pending work while retaining the last displayed frame until its normal expiry.
    /// Only an explicit producer reset clears the displayed frame immediately.
    private func clearTimeline() {
        pending.removeAll(keepingCapacity: true)
        sourceOrigin = nil
        hostOrigin = nil
        lastTimestamp = nil
        lastPresentationTime = nil
        nextPresentationTime = nil
    }
}
