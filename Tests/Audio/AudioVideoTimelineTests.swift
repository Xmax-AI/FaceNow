import XCTest
import CoreVideo
@testable import CameraCore

final class AudioVideoTimelineTests: XCTestCase {
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
