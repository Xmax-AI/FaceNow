import XCTest
import CoreVideo
@testable import CameraCore

final class AudioVideoTimelineTests: XCTestCase {
    func testTwoSecondVideoHoldPreservesAudioClockAndHighRateFrames() throws {
        let store = ScheduledFrameStore(capacity: 320, maximumVideoDelay: 2)
        let producer = UUID()
        store.reset(producer: producer, videoDelay: 2)
        let pixels = try makePixels()
        for index in 0..<240 {
            let step = Double(index) / 120
            store.submit(pixels, producer: producer, timestamp: 10 + step, duration: 1.0 / 120, now: 100 + step)
        }
        XCTAssertEqual(store.pendingFrameCount, 240)
        XCTAssertNil(store.frame(now: 102))
        let frame = try XCTUnwrap(store.frame(now: 102 + 1.0 / 30))
        XCTAssertEqual(frame.presentationTime, 102 + 1.0 / 30, accuracy: 0.00001)
        XCTAssertEqual(
            try XCTUnwrap(store.presentationTime(forSourceTimestamp: 11.99, producer: producer)),
            100 + 1.0 / 30 + 1.99,
            accuracy: 0.00001
        )
        XCTAssertEqual(store.takeStatistics().overflow, 0)
    }

    func testOwnedDelayFramesReleaseProducerPoolAndPreservePixelsAndMetadata() throws {
        for format in [kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange] {
            try checkOwnedFrames(pixelFormat: format)
        }
    }

    private func checkOwnedFrames(
        pixelFormat: OSType
    ) throws {
        var pool: CVPixelBufferPool?
        XCTAssertEqual(
            CVPixelBufferPoolCreate(
                nil,
                nil,
                [
                    kCVPixelBufferWidthKey: 2,
                    kCVPixelBufferHeightKey: 2,
                    kCVPixelBufferPixelFormatTypeKey: pixelFormat,
                ] as CFDictionary,
                &pool
            ),
            kCVReturnSuccess
        )
        let sourcePool = try XCTUnwrap(pool)
        let store = ScheduledFrameStore(capacity: 320, maximumVideoDelay: 2, copiesFrames: true)
        let producer = UUID()
        store.reset(producer: producer, videoDelay: 2)
        for index in 0..<20 {
            try autoreleasepool {
                var buffer: CVPixelBuffer?
                XCTAssertEqual(
                    CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
                        nil,
                        sourcePool,
                        [kCVPixelBufferPoolAllocationThresholdKey: 2] as CFDictionary,
                        &buffer
                    ),
                    kCVReturnSuccess
                )
                let source = try XCTUnwrap(buffer)
                CVBufferSetAttachment(source, "test.lease" as CFString, NSObject(), .shouldNotPropagate)
                CVBufferSetAttachment(
                    source,
                    kCVImageBufferColorPrimariesKey,
                    kCVImageBufferColorPrimaries_ITU_R_709_2,
                    .shouldPropagate
                )
                paint(source, value: UInt8(index))
                let step = Double(index) / 60
                store.submit(source, producer: producer, timestamp: 10 + step, duration: 1.0 / 60, now: 100 + step)
                paint(source, value: 240)
            }
        }
        let frame = try XCTUnwrap(store.frame(now: 102 + 1.0 / 30))
        CVPixelBufferLockBaseAddress(frame.pixelBuffer, .readOnly)
        let planes = CVPixelBufferGetPlaneCount(frame.pixelBuffer)
        for plane in 0..<max(1, planes) {
            let address = planes > 0
                ? CVPixelBufferGetBaseAddressOfPlane(frame.pixelBuffer, plane)
                : CVPixelBufferGetBaseAddress(frame.pixelBuffer)
            XCTAssertEqual(address!.load(as: UInt8.self), UInt8(plane))
        }
        CVPixelBufferUnlockBaseAddress(frame.pixelBuffer, .readOnly)
        XCTAssertNil(CVBufferCopyAttachment(frame.pixelBuffer, "test.lease" as CFString, nil))
        XCTAssertNotNil(CVBufferCopyAttachment(frame.pixelBuffer, kCVImageBufferColorPrimariesKey, nil))
    }

    private func paint(
        _ buffer: CVPixelBuffer,
        value: UInt8
    ) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let planes = CVPixelBufferGetPlaneCount(buffer)
        for plane in 0..<max(1, planes) {
            let address = planes > 0
                ? CVPixelBufferGetBaseAddressOfPlane(buffer, plane) : CVPixelBufferGetBaseAddress(buffer)
            let stride = planes > 0
                ? CVPixelBufferGetBytesPerRowOfPlane(buffer, plane) : CVPixelBufferGetBytesPerRow(buffer)
            let height = planes > 0 ? CVPixelBufferGetHeightOfPlane(buffer, plane) : CVPixelBufferGetHeight(buffer)
            memset(address!, Int32(value) + Int32(plane), stride * height)
        }
    }

    func testReducingHoldSkipsBacklogAndRejectsOldSessionChanges() throws {
        let store = ScheduledFrameStore(capacity: 96, maximumVideoDelay: 0.5)
        let producer = UUID()
        store.reset(producer: producer, videoDelay: 0.5)
        var newest: CVPixelBuffer?
        for index in 0..<26 {
            let pixels = try makePixels()
            let step = Double(index) / 60
            store.submit(pixels, producer: producer, timestamp: 10 + step, duration: 1.0 / 60, now: 100 + step)
            newest = pixels
        }
        XCTAssertNil(store.frame(now: 100.45))
        store.setVideoDelay(0, producer: producer)
        let caughtUp = try XCTUnwrap(store.frame(now: 100.45))
        XCTAssertTrue(caughtUp.pixelBuffer === newest)
        XCTAssertEqual(store.pendingFrameCount, 0)
        let replacement = UUID()
        store.reset(producer: replacement)
        store.setVideoDelay(0.5, producer: producer)
        let pixels = try makePixels()
        store.submit(pixels, producer: replacement, timestamp: 20, now: 101)
        XCTAssertNotNil(store.frame(now: 101 + 1.0 / 30))
        XCTAssertNil(store.presentationTime(forSourceTimestamp: 20, producer: producer))
    }

    private func makePixels() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 2, 2, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        return try XCTUnwrap(buffer)
    }

    func testAudioFollowsActualVideoDeadlineAndCannotCrossSession() throws {
        let store = ScheduledFrameStore()
        let producer = UUID()
        store.reset(producer: producer)
        XCTAssertNil(store.presentationTime(forSourceTimestamp: 10, producer: producer))
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 2, 2, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        store.submit(pixels, producer: producer, timestamp: 10, duration: 1.0 / 30, now: 100)
        XCTAssertEqual(
            try XCTUnwrap(store.presentationTime(forSourceTimestamp: 10.01, producer: producer)),
            100 + 1.0 / 30 + 0.01,
            accuracy: 0.00001
        )
        // A late processed video frame rebases its actual display interval; audio follows that interval.
        store.submit(pixels, producer: producer, timestamp: 10.04, duration: 1.0 / 30, now: 100.08)
        XCTAssertEqual(
            try XCTUnwrap(store.presentationTime(forSourceTimestamp: 10.05, producer: producer)),
            100.08 + 1.0 / 30 + 0.01,
            accuracy: 0.00001
        )
        XCTAssertNil(store.presentationTime(forSourceTimestamp: 20, producer: producer))
        store.reset(producer: UUID())
        XCTAssertNil(store.presentationTime(forSourceTimestamp: 10.05, producer: producer))
    }
}
