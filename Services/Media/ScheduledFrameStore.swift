//
//  ScheduledFrameStore.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
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
    private let capacity = 8

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

    /// The next host-clock presentation slot reserved for an interpolation burst.
    private var nextPresentationTime: TimeInterval?

    /// The queue discard counters read and reset under the same state lock.
    private var statistics = FrameQueueStatistics()

    /// SDK timestamps are rebased once; CMIO input already uses the host clock.
    init(
        usesHostTime: Bool = false,
        playoutDelay: TimeInterval = 1.0 / 30,
        staleInterval: TimeInterval = 2
    ) {
        self.usesHostTime = usesHostTime
        self.playoutDelay = playoutDelay
        self.staleInterval = staleInterval
    }

    /// A new producer invalidates every queued frame and the previous timeline.
    func reset(
        producer: UUID?
    ) {
        lock.lock()
        defer { lock.unlock() }
        self.producer = producer
        clearTimeline()
        displayed = nil
        statistics = FrameQueueStatistics()
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
        pending.append(
            ScheduledVideoFrame(
                pixelBuffer: pixelBuffer,
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

    /// Presents due frames in order; lower-rate consumers may skip to the latest due frame.
    func frame(
        now: TimeInterval,
        preferLatest: Bool = false
    ) -> ScheduledVideoFrame? {
        lock.lock()
        defer { lock.unlock() }
        let previousCount = pending.count
        pending.removeAll {
            now - $0.receivedAt >= staleInterval || now - $0.presentationTime > maximumLatency
        }
        statistics.expired += previousCount - pending.count
        var selectedCount = 0
        while let first = pending.first, first.presentationTime <= now + 0.0005 {
            displayed = pending.removeFirst()
            selectedCount += 1
            if !preferLatest { break }
        }
        statistics.superseded += max(0, selectedCount - 1)
        guard let displayed, now >= displayed.receivedAt,
            now - displayed.receivedAt < staleInterval
        else {
            self.displayed = nil
            return nil
        }
        return displayed
    }

    /// Reports retained work for diagnostics without exposing queue mutation.
    var pendingFrameCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }

    /// Drains interval counters without changing queued frames or their presentation times.
    func takeStatistics() -> FrameQueueStatistics {
        lock.lock()
        defer { lock.unlock() }
        let result = statistics
        statistics = FrameQueueStatistics()
        return result
    }

    /// Rebases pending work while retaining the last displayed frame until its normal expiry.
    /// Only an explicit producer reset clears the displayed frame immediately.
    private func clearTimeline() {
        pending.removeAll(keepingCapacity: true)
        sourceOrigin = nil
        hostOrigin = nil
        lastTimestamp = nil
        nextPresentationTime = nil
    }
}
