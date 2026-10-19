//
//  LatestFrameStore.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreVideo
import Foundation

/// An immutable frame reference retained while the consumer renders it.
struct VideoFrame: @unchecked Sendable {
    /// The pixel buffer remains owned for the lifetime of this value.
    let pixelBuffer: CVPixelBuffer

    /// The monotonic time at which the producer received the frame.
    let receivedAt: TimeInterval
}

/// A single-slot mailbox; the lock protects both the frame and producer generation.
final class LatestFrameStore: @unchecked Sendable {
    /// The lock guarding mutable storage.
    private let lock = NSLock()

    /// The current producer token rejects late callbacks after stopping or restarting.
    private var producer: UUID?

    /// The most recently submitted frame; older frames are released immediately.
    private var frame: VideoFrame?

    /// Replaces the producer and discards all frames from the previous session.
    func reset(producer: UUID?) {
        lock.lock()
        defer { lock.unlock() }
        self.producer = producer
        frame = nil
    }

    /// Stores a frame only while its producer still owns the mailbox.
    func submit(_ pixelBuffer: CVPixelBuffer, producer: UUID, now: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard self.producer == producer else { return }
        frame = VideoFrame(pixelBuffer: pixelBuffer, receivedAt: now)
    }

    /// Returns a fresh frame without transferring ownership out of the mailbox.
    func latest(now: TimeInterval) -> VideoFrame? {
        lock.lock()
        defer { lock.unlock() }
        guard let frame, now >= frame.receivedAt,
              now - frame.receivedAt < CameraConfiguration.staleInterval else {
            self.frame = nil
            return nil
        }
        return frame
    }
}
