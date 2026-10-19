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
    let pixelBuffer: CVPixelBuffer
    let receivedAt: TimeInterval
    let presentationTime: TimeInterval
}

/// Counts discarded transport samples separately from repeated output frames.
struct FrameQueueStatistics {
    var overflow = 0
    var expired = 0
    var superseded = 0
    var discontinuity = 0
}

/// Preserves interpolation bursts in a bounded queue without blocking SDK delivery.
final class ScheduledFrameStore: @unchecked Sendable {
    /// The timeline mode and maximum pending work.
    private let usesHostTime: Bool
    private let playoutDelay: TimeInterval
    private let capacity = 8
    private let maximumLatency: TimeInterval = 0.15

    /// The lock protects producer ownership, timeline mapping and retained frames.
    private let lock = NSLock()
    private var producer: UUID?
    private var pending: [ScheduledVideoFrame] = []
    private var displayed: ScheduledVideoFrame?
    private var sourceOrigin: TimeInterval?
    private var hostOrigin: TimeInterval?
    private var lastTimestamp: TimeInterval?
    private var nextPresentationTime: TimeInterval?
    private var statistics = FrameQueueStatistics()

    /// SDK timestamps are rebased once; CMIO input already uses the host clock.
    init(usesHostTime: Bool = false, playoutDelay: TimeInterval = 1.0 / 30) {
        self.usesHostTime = usesHostTime
        self.playoutDelay = playoutDelay
    }

    /// A new producer invalidates every queued frame and the previous timeline.
    func reset(producer: UUID?) {
        lock.lock()
        defer { lock.unlock() }
        self.producer = producer
        clearTimeline()
        displayed = nil
        statistics = FrameQueueStatistics()
    }

    /// Retains frames in timestamp order, rebasing interrupted or discontinuous timelines.
    func submit(_ pixelBuffer: CVPixelBuffer, producer: UUID, timestamp: TimeInterval,
                duration: TimeInterval? = nil, now: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard self.producer == producer, now.isFinite else { return }
        let timestamp = timestamp.isFinite ? timestamp : (lastTimestamp.map { $0 + 1.0 / 60 } ?? now)
        if let lastTimestamp {
            if timestamp == lastTimestamp { return }
            if timestamp < lastTimestamp || timestamp - lastTimestamp > CameraConfiguration.staleInterval {
                statistics.discontinuity += pending.count
                clearTimeline()
            }
        }
        if sourceOrigin == nil { sourceOrigin = timestamp; hostOrigin = now + playoutDelay }
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
        pending.append(ScheduledVideoFrame(pixelBuffer: pixelBuffer, receivedAt: now, presentationTime: due))
        if pending.count > capacity {
            let count = pending.count - capacity
            statistics.overflow += count
            pending.removeFirst(count)
        }
    }

    /// Presents due frames in order; lower-rate consumers may skip to the latest due frame.
    func frame(now: TimeInterval, preferLatest: Bool = false) -> ScheduledVideoFrame? {
        lock.lock()
        defer { lock.unlock() }
        let previousCount = pending.count
        pending.removeAll { now - $0.receivedAt >= CameraConfiguration.staleInterval || now - $0.presentationTime > maximumLatency }
        statistics.expired += previousCount - pending.count
        var selectedCount = 0
        while let first = pending.first, first.presentationTime <= now + 0.0005 {
            displayed = pending.removeFirst()
            selectedCount += 1
            if !preferLatest { break }
        }
        statistics.superseded += max(0, selectedCount - 1)
        guard let displayed, now >= displayed.receivedAt,
              now - displayed.receivedAt < CameraConfiguration.staleInterval else {
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
