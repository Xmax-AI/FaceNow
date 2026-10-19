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
        let store = LatestFrameStore()
        let old = UUID()
        let current = UUID()
        let buffer = try makeBuffer()
        store.reset(producer: old)
        store.submit(buffer, producer: old, now: 10)
        store.reset(producer: current)
        store.submit(buffer, producer: old, now: 11)
        XCTAssertNil(store.latest(now: 11))
        store.submit(buffer, producer: current, now: 12)
        XCTAssertNotNil(store.latest(now: 12))
        store.reset(producer: nil)
        store.submit(buffer, producer: current, now: 13)
        XCTAssertNil(store.latest(now: 13))
    }

    /// A slow consumer sees only the newest frame, with a strict expiry.
    func testLatestFrameAndStaleness() throws {
        let store = LatestFrameStore()
        let producer = UUID()
        store.reset(producer: producer)
        let first = try makeBuffer()
        let latest = try makeBuffer()
        store.submit(first, producer: producer, now: 10)
        store.submit(latest, producer: producer, now: 11)
        XCTAssertTrue(store.latest(now: 11.5)?.pixelBuffer === latest)
        XCTAssertNil(store.latest(now: 13))
    }

    /// Concurrent SDK delivery and stop operations cannot revive expired sessions.
    func testConcurrentHandoffRemainsStopped() throws {
        let store = LatestFrameStore()
        let producer = UUID()
        let frame = VideoFrame(pixelBuffer: try makeBuffer(), receivedAt: 1)
        store.reset(producer: producer)
        DispatchQueue.concurrentPerform(iterations: 1000) { index in
            if index.isMultiple(of: 5) { store.reset(producer: nil) }
            store.submit(frame.pixelBuffer, producer: producer, now: Double(index))
            _ = store.latest(now: Double(index))
        }
        XCTAssertNil(store.latest(now: 1000))
    }

    /// Wide and portrait model outputs are centered with their aspect ratio intact.
    func testAspectFitPreservesImage() {
        let wide = VideoFrameRenderer.fittedRect(width: 1920, height: 1024)
        XCTAssertEqual(wide.width, 1280, accuracy: 0.01)
        XCTAssertEqual(wide.height, 682.6667, accuracy: 0.01)
        XCTAssertEqual(wide.midY, 360, accuracy: 0.01)
        let portrait = VideoFrameRenderer.fittedRect(width: 1024, height: 1920)
        XCTAssertEqual(portrait.height, 720, accuracy: 0.01)
        XCTAssertEqual(portrait.width, 384, accuracy: 0.01)
        XCTAssertEqual(portrait.midX, 640, accuracy: 0.01)
        XCTAssertEqual(VideoFrameRenderer.fittedRect(width: 0, height: 0), .zero)
    }

    /// Both generated input formats produce the same NV12 camera contract.
    func testBGRAAndNV12Normalization() throws {
        let renderer = try VideoFrameRenderer()
        for format in [kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange] {
            let output = try renderer.normalize(makeBuffer(format: format))
            XCTAssertEqual(CVPixelBufferGetWidth(output), 1280)
            XCTAssertEqual(CVPixelBufferGetHeight(output), 720)
            XCTAssertEqual(CVPixelBufferGetPixelFormatType(output), CameraConfiguration.pixelFormat)
            XCTAssertEqual(CVPixelBufferGetPlaneCount(output), 2)
            XCTAssertNotNil(CVPixelBufferGetIOSurface(output))
        }
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
        XCTAssertEqual(CMVideoFormatDescriptionGetDimensions(description).width, 1280)
        let image = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
        XCTAssertTrue(CMVideoFormatDescriptionMatchesImageBuffer(renderer.formatDescription, imageBuffer: image))
    }

    /// Horizontal orientation is preserved and aspect-fit padding is opaque black.
    func testNormalizationDoesNotMirrorAndPadsBlack() throws {
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
        let row = 360 * stride
        XCTAssertGreaterThan(Int(luma[row + 300]), Int(luma[row + 900]) + 15)
        XCTAssertEqual(Int(luma[row]), 16, accuracy: 2)
        XCTAssertEqual(Int(luma[row + 1279]), 16, accuracy: 2)
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
