import CoreMedia
import CoreVideo
import XCTest
@testable import CameraCore

final class MediaConfigurationTests: XCTestCase {

    func testRendererUsesTheCallersCanvasAndCadence() throws {
        let format = VideoFormat(
            width: 640,
            height: 360,
            frameRate: 30,
            pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        )
        let renderer = try VideoFrameRenderer(format: format)
        let frame = try renderer.waiting()
        XCTAssertEqual(
            CVPixelBufferGetWidth(frame),
            640
        )
        XCTAssertEqual(
            CVPixelBufferGetHeight(frame),
            360
        )
        XCTAssertEqual(
            CVPixelBufferGetPixelFormatType(frame),
            format.pixelFormat
        )
        let sample = try renderer.sampleBuffer(
            frame,
            at: .zero
        )
        XCTAssertEqual(
            CMSampleBufferGetDuration(sample),
            CMTime(
                value: 1,
                timescale: 30
            )
        )
    }

    func testFrameStoreHonorsTheCallersStalenessPolicy() throws {
        let store = ScheduledFrameStore(
            playoutDelay: 0,
            staleInterval: 0.25
        )
        let producer = UUID()
        let renderer = try VideoFrameRenderer(
            format: VideoFormat(
                width: 16,
                height: 16,
                frameRate: 30,
                pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            )
        )
        store.reset(producer: producer)
        let frame = try renderer.waiting()
        store.submit(
            frame,
            producer: producer,
            timestamp: 10,
            now: 10
        )
        XCTAssertNotNil(store.frame(now: 10))
        XCTAssertNotNil(store.frame(now: 10.24))
        XCTAssertNil(store.frame(now: 10.25))
    }
}
