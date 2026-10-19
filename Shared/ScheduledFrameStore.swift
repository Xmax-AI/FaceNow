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
        clear()
    }

    /// Retains frames in timestamp order, rebasing interrupted or discontinuous timelines.
    func submit(_ pixelBuffer: CVPixelBuffer, producer: UUID, timestamp: TimeInterval, now: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard self.producer == producer, now.isFinite else { return }
        let timestamp = timestamp.isFinite ? timestamp : (lastTimestamp.map { $0 + 1.0 / 60 } ?? now)
        if let lastTimestamp {
            if timestamp == lastTimestamp { return }
            if timestamp < lastTimestamp || timestamp - lastTimestamp > CameraConfiguration.staleInterval { clear() }
        }
        if sourceOrigin == nil { sourceOrigin = timestamp; hostOrigin = now + playoutDelay }
        var due = usesHostTime ? timestamp + playoutDelay : hostOrigin! + timestamp - sourceOrigin!
        if !usesHostTime, abs(due - now) > maximumLatency {
            clear()
            sourceOrigin = timestamp
            hostOrigin = now + playoutDelay
            due = hostOrigin!
        }
        lastTimestamp = timestamp
        pending.append(ScheduledVideoFrame(pixelBuffer: pixelBuffer, receivedAt: now, presentationTime: due))
        if pending.count > capacity { pending.removeFirst(pending.count - capacity) }
    }

    /// Presents due frames in order; lower-rate consumers may skip to the latest due frame.
    func frame(now: TimeInterval, preferLatest: Bool = false) -> ScheduledVideoFrame? {
        lock.lock()
        defer { lock.unlock() }
        pending.removeAll { now - $0.receivedAt >= CameraConfiguration.staleInterval || now - $0.presentationTime > maximumLatency }
        while let first = pending.first, first.presentationTime <= now + 0.0005 {
            displayed = pending.removeFirst()
            if !preferLatest { break }
        }
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

    /// Clears timeline state while the caller holds the lock.
    private func clear() {
        pending.removeAll(keepingCapacity: true)
        displayed = nil
        sourceOrigin = nil
        hostOrigin = nil
        lastTimestamp = nil
    }
}
