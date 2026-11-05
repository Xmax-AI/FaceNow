import XCTest
import AVFoundation
import AudioTimelineBuffer
@testable import CameraCore
@testable import VirtualMicrophoneCore

final class AudioPCMConverterTests: XCTestCase {
    func testMonoBecomesIdenticalStereoWithoutMonitoringGain() throws {
        let converter = AudioPCMConverter()
        let source = [Int16](repeating: 16_384, count: 480)
        let data = source.withUnsafeBytes { Data($0) }
        let output = try converter.convert(
            data: data,
            sourceRate: 48_000,
            channels: 1,
            samplesPerChannel: 480,
            outputRate: 48_000
        )
        XCTAssertEqual(output.frameLength, 480)
        let samples = output.floatChannelData![0]
        for i in 0..<Int(output.frameLength) {
            XCTAssertEqual(samples[i * 2], 0.5, accuracy: 0.001)
            XCTAssertEqual(samples[i * 2 + 1], samples[i * 2])
        }
    }

    func testStereoPreservesChannelOrderAndPolarity() throws {
        let converter = AudioPCMConverter()
        let source = (0..<480).flatMap { _ in [Int16(8192), Int16(-8192)] }
        let output = try converter.convert(
            data: source.withUnsafeBytes { Data($0) },
            sourceRate: 48_000,
            channels: 2,
            samplesPerChannel: 480,
            outputRate: 48_000
        )
        XCTAssertEqual(output.frameLength, 480)
        XCTAssertEqual(output.floatChannelData![0][0], 0.25, accuracy: 0.001)
        XCTAssertEqual(output.floatChannelData![0][1], -0.25, accuracy: 0.001)
    }

    func testStreamingResamplerAndDeviceRateChanges() throws {
        let converter = AudioPCMConverter()
        let data = [Int16](repeating: 8192, count: 160).withUnsafeBytes { Data($0) }
        for rate in [48_000.0, 44_100.0, 48_000.0] {
            var frames: UInt32 = 0
            for _ in 0..<100 {
                let output = try converter.convert(
                    data: data,
                    sourceRate: 16_000,
                    channels: 1,
                    samplesPerChannel: 160,
                    outputRate: rate
                )
                frames += output.frameLength
                for i in 0..<Int(output.frameLength) {
                    XCTAssertTrue(output.floatChannelData![0][i * 2].isFinite)
                }
            }
            XCTAssertEqual(Double(frames), rate, accuracy: 200)
        }
    }

    func testMalformedPCMIsRejected() {
        let converter = AudioPCMConverter()
        XCTAssertThrowsError(
            try converter.convert(
                data: Data([0]),
                sourceRate: 48_000,
                channels: 1,
                samplesPerChannel: 480,
                outputRate: 48_000
            )
        )
        XCTAssertThrowsError(
            try converter.convert(
                data: Data(),
                sourceRate: 0,
                channels: 0,
                samplesPerChannel: Int.max,
                outputRate: .nan
            )
        )
    }

    func testConvertedAudioSchedulesIntoRenderCallbackAtExactHostTime() throws {
        let converter = AudioPCMConverter()
        let output = try converter.convert(
            data: [Int16](repeating: 16_384, count: 480).withUnsafeBytes { Data($0) },
            sourceRate: 48_000,
            channels: 1,
            samplesPerChannel: 480,
            outputRate: 48_000
        )
        let ring = try XCTUnwrap(AudioTimelineBufferCreate(48_000))
        defer { AudioTimelineBufferDestroy(ring) }
        let host = mach_absolute_time()
        AudioTimelineBufferSchedule(
            ring,
            AVAudioTime.seconds(forHostTime: host),
            output.floatChannelData![0],
            output.frameLength
        )
        var samples = [Float](repeating: 0, count: 960)
        samples.withUnsafeMutableBytes { bytes in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: UInt32(bytes.count),
                    mData: bytes.baseAddress
                )
            )
            var stamp = AudioTimeStamp(); stamp.mHostTime = host; stamp.mFlags = .hostTimeValid
            var flags: AudioUnitRenderActionFlags = []
            XCTAssertEqual(
                AudioTimelineBufferRender(UnsafeMutableRawPointer(ring), &flags, &stamp, 0, 480, &list),
                noErr
            )
        }
        XCTAssertEqual(samples[0], 0.5, accuracy: 0.001)
        AudioTimelineBufferReset(ring)
        samples.withUnsafeMutableBufferPointer { pointer in
            XCTAssertEqual(AudioTimelineBufferRead(ring, 0, pointer.baseAddress, 480), 0)
        }
        XCTAssertTrue(samples.allSatisfy { $0 == 0 })
    }
}
