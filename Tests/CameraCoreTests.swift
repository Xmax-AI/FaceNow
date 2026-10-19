//
//  CameraCoreTests.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreMedia
import CoreVideo
import XCTest
@testable import CameraCore

/// Exercises media contracts and bounded handoff without camera hardware or a service connection.
final class CameraCoreTests: XCTestCase {
    /// A stopped producer cannot repopulate the mailbox with a late SDK callback.
    func testRestartRejectsOldProducer() throws {
        let store = ScheduledFrameStore(playoutDelay: 0)
        let old = UUID()
        let current = UUID()
        let buffer = try makeBuffer()
        store.reset(producer: old)
        store.submit(buffer, producer: old, timestamp: 10, now: 10)
        XCTAssertTrue(store.frame(now: 10)?.pixelBuffer === buffer)
        store.reset(producer: current)
        store.submit(buffer, producer: old, timestamp: 11, now: 11)
        XCTAssertNil(store.frame(now: 11))
        store.submit(buffer, producer: current, timestamp: 12, now: 12)
        XCTAssertNotNil(store.frame(now: 12))
        store.reset(producer: nil)
        store.submit(buffer, producer: current, timestamp: 13, now: 13)
        XCTAssertNil(store.frame(now: 13))
    }

    /// A slow consumer sees only the newest frame, with a strict expiry.
    func testLatestFrameAndStaleness() throws {
        let store = ScheduledFrameStore(playoutDelay: 0)
        let producer = UUID()
        store.reset(producer: producer)
        let first = try makeBuffer()
        let latest = try makeBuffer()
        store.submit(first, producer: producer, timestamp: 10, now: 10)
        _ = store.frame(now: 10)
        store.submit(latest, producer: producer, timestamp: 11, now: 11)
        _ = store.frame(now: 11)
        XCTAssertTrue(store.frame(now: 11.5)?.pixelBuffer === latest)
        XCTAssertNil(store.frame(now: 13))
    }

    /// Concurrent SDK delivery and stop operations cannot revive expired sessions.
    func testConcurrentHandoffRemainsStopped() throws {
        let store = ScheduledFrameStore(playoutDelay: 0)
        let producer = UUID()
        let frame = try makeBuffer()
        store.reset(producer: producer)
        DispatchQueue.concurrentPerform(iterations: 1000) { index in
            if index.isMultiple(of: 5) { store.reset(producer: nil) }
            store.submit(frame, producer: producer, timestamp: Double(index), now: Double(index))
            _ = store.frame(now: Double(index))
        }
        XCTAssertNil(store.frame(now: 1000))
    }

    /// Intermediate and original frames arriving together retain separate display slots.
    func testInterpolationBurstPreservesPresentationOrder() throws {
        let store = ScheduledFrameStore(playoutDelay: 0.04)
        let producer = UUID()
        store.reset(producer: producer)
        let first = try makeBuffer()
        let intermediate = try makeBuffer()
        let original = try makeBuffer()
        store.submit(first, producer: producer, timestamp: 100, now: 10)
        store.submit(intermediate, producer: producer, timestamp: 100 + 1.0 / 60, now: 10 + 1.0 / 30)
        store.submit(original, producer: producer, timestamp: 100 + 1.0 / 30, now: 10 + 1.0 / 30)
        XCTAssertNil(store.frame(now: 10.03))
        XCTAssertTrue(store.frame(now: 10.04)?.pixelBuffer === first)
        XCTAssertTrue(store.frame(now: 10.04 + 1.0 / 60)?.pixelBuffer === intermediate)
        XCTAssertTrue(store.frame(now: 10.04 + 1.0 / 30)?.pixelBuffer === original)
    }

    /// A 60 fps transport preserves 48 fps interpolation bursts without overwriting intermediate frames.
    func testSixtyFpsConsumerPreservesFortyEightFpsBursts() throws {
        let store = ScheduledFrameStore(playoutDelay: 0.05)
        let producer = UUID()
        store.reset(producer: producer)
        let frames = try (0..<97).map { _ in try makeBuffer() }
        var submitted = 0
        var presented: [Int] = []
        for tick in 0..<130 {
            let now = Double(tick) / 60
            while submitted < frames.count {
                let arrival = submitted == 0 ? 0 : Double((submitted + 1) / 2) / 24
                guard arrival <= now + 0.000001 else { break }
                store.submit(frames[submitted], producer: producer, timestamp: Double(submitted) / 48, now: arrival)
                submitted += 1
            }
            if let frame = store.frame(now: now), let index = frames.firstIndex(where: { $0 === frame.pixelBuffer }),
               presented.last != index { presented.append(index) }
        }
        XCTAssertEqual(presented, Array(frames.indices))
    }

    /// Lower-rate clients select the newest due frame instead of accumulating latency.
    func testThirtyFpsConsumerSkipsDueFramesAndQueueIsBounded() throws {
        let store = ScheduledFrameStore(usesHostTime: true, playoutDelay: 0)
        let producer = UUID()
        store.reset(producer: producer)
        let frames = try (0..<20).map { _ in try makeBuffer() }
        for index in frames.indices {
            store.submit(frames[index], producer: producer, timestamp: 10 + Double(index) / 1000, now: 10)
        }
        XCTAssertEqual(store.pendingFrameCount, 8)
        XCTAssertTrue(store.frame(now: 10.03, preferLatest: true)?.pixelBuffer === frames.last!)
        XCTAssertEqual(store.pendingFrameCount, 0)
    }

    /// Stalls and timestamp restarts cannot leave an old queue ahead of the current session.
    func testTimelineRestartRebasesAndExpiredFramesAreReleased() throws {
        let store = ScheduledFrameStore(playoutDelay: 0.04)
        let producer = UUID()
        store.reset(producer: producer)
        let first = try makeBuffer()
        let restarted = try makeBuffer()
        store.submit(first, producer: producer, timestamp: 100, now: 1)
        store.submit(restarted, producer: producer, timestamp: 1, now: 2)
        XCTAssertNil(store.frame(now: 2))
        XCTAssertTrue(store.frame(now: 2.04)?.pixelBuffer === restarted)
        XCTAssertNil(store.frame(now: 4.1))
        let resumed = try makeBuffer()
        store.submit(resumed, producer: producer, timestamp: 1.02, now: 5)
        XCTAssertNil(store.frame(now: 5))
        XCTAssertTrue(store.frame(now: 5.04)?.pixelBuffer === resumed)
    }

    /// Effect timeline changes retain the displayed frame while the replacement waits for its display slot.
    func testTimelineChangesDoNotFlashWaitingFrame() throws {
        for timestamp in [1.0, 103.0, 100.04] {
            let store = ScheduledFrameStore(playoutDelay: 0.04)
            let producer = UUID()
            store.reset(producer: producer)
            let displayed = try makeBuffer()
            let discarded = try makeBuffer()
            let replacement = try makeBuffer()
            store.submit(displayed, producer: producer, timestamp: 100, now: 1)
            XCTAssertTrue(store.frame(now: 1.04)?.pixelBuffer === displayed)
            store.submit(discarded, producer: producer, timestamp: 100.02, now: 1.04)
            store.submit(replacement, producer: producer, timestamp: timestamp, now: 1.4)
            XCTAssertEqual(store.pendingFrameCount, 1)
            XCTAssertTrue(store.frame(now: 1.4)?.pixelBuffer === displayed)
            XCTAssertTrue(store.frame(now: 1.42)?.pixelBuffer === displayed)
            XCTAssertTrue(store.frame(now: 1.44)?.pixelBuffer === replacement)
            XCTAssertNil(store.frame(now: 3.5))
        }
    }

    /// Both generated input formats produce the same NV12 camera contract.
    func testBGRAAndNV12Normalization() throws {
        let renderer = try VideoFrameRenderer()
        for format in [kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange] {
            let output = try renderer.normalize(makeBuffer(format: format))
            XCTAssertEqual(CVPixelBufferGetWidth(output), 1920)
            XCTAssertEqual(CVPixelBufferGetHeight(output), 1024)
            XCTAssertEqual(CVPixelBufferGetPixelFormatType(output), CameraConfiguration.pixelFormat)
            XCTAssertEqual(CVPixelBufferGetPlaneCount(output), 2)
            XCTAssertNotNil(CVPixelBufferGetIOSurface(output))
        }
    }

    /// Compatible buffers bypass allocation even when the conversion pool is exhausted.
    func testCompatibleBufferPassesThroughWithoutAllocation() throws {
        let renderer = try VideoFrameRenderer()
        let held = try (0..<8).map { _ in try renderer.waiting() }
        XCTAssertThrowsError(try renderer.waiting())
        let output = try renderer.normalize(held[0])
        XCTAssertTrue(output === held[0])
        let sample = try renderer.sampleBuffer(output, at: .zero)
        XCTAssertTrue(CMSampleBufferGetImageBuffer(sample) === held[0])
    }

    /// Missing color metadata requires conversion without retagging the SDK-owned input.
    func testMissingColorMetadataUsesConversion() throws {
        let renderer = try VideoFrameRenderer()
        let input = try renderer.waiting()
        CVBufferRemoveAttachment(input, kCVImageBufferColorPrimariesKey)
        let output = try renderer.normalize(input)
        XCTAssertFalse(output === input)
        XCTAssertTrue(CMVideoFormatDescriptionMatchesImageBuffer(renderer.formatDescription, imageBuffer: output))
        XCTAssertFalse(CMVideoFormatDescriptionMatchesImageBuffer(renderer.formatDescription, imageBuffer: input))
    }

    /// Source samples carry host timestamps and fixed camera durations.
    func testSampleTimingAndFormat() throws {
        let renderer = try VideoFrameRenderer()
        let time = CMTime(value: 123456789, timescale: 1_000_000)
        let sample = try renderer.sampleBuffer(renderer.testPattern(at: 0), at: time)
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sample), time)
        XCTAssertEqual(CMSampleBufferGetDuration(sample), CameraConfiguration.frameDuration)
        let description = try XCTUnwrap(CMSampleBufferGetFormatDescription(sample))
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(description), CameraConfiguration.pixelFormat)
        XCTAssertEqual(CMVideoFormatDescriptionGetDimensions(description).width, 1920)
        let image = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
        XCTAssertTrue(CMVideoFormatDescriptionMatchesImageBuffer(renderer.formatDescription, imageBuffer: image))
    }

    /// Horizontal orientation is preserved and image content reaches every output edge.
    func testNormalizationDoesNotMirrorOrAddPadding() throws {
        let input = try makeBuffer()
        CVPixelBufferLockBaseAddress(input, [])
        let bytes = CVPixelBufferGetBaseAddress(input)!.assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(input)
        for row in 0..<128 {
            for column in 0..<192 {
                let offset = row * rowBytes + column * 4
                bytes[offset] = column < 96 ? 0 : 255
                bytes[offset + 1] = 0
                bytes[offset + 2] = column < 96 ? 255 : 0
                bytes[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(input, [])
        let output = try VideoFrameRenderer().normalize(input)
        CVPixelBufferLockBaseAddress(output, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(output, .readOnly) }
        let luma = CVPixelBufferGetBaseAddressOfPlane(output, 0)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(output, 0)
        let row = 512 * stride
        XCTAssertGreaterThan(Int(luma[row + 300]), Int(luma[row + 1440]) + 15)
        XCTAssertEqual(Int(luma[row]), Int(luma[row + 300]), accuracy: 2)
        XCTAssertEqual(Int(luma[row + 1919]), Int(luma[row + 1440]), accuracy: 2)
        XCTAssertEqual(Int(luma[300]), Int(luma[row + 300]), accuracy: 2)
        XCTAssertEqual(Int(luma[1023 * stride + 1440]), Int(luma[row + 1440]), accuracy: 2)
    }

    /// Holding frames applies backpressure rather than allowing pool growth without bound.
    func testPoolIsBoundedAndRecovers() throws {
        let renderer = try VideoFrameRenderer()
        var held = [CVPixelBuffer]()
        for _ in 0..<8 { held.append(try renderer.waiting()) }
        XCTAssertThrowsError(try renderer.waiting())
        held.removeAll()
        XCTAssertNoThrow(try renderer.waiting())
    }

    /// Allocates either supported source format independently of camera hardware.
    private func makeBuffer(format: OSType = kCVPixelFormatType_32BGRA) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, 192, 128, format,
                                        [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &buffer)
        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(buffer)
    }
}
