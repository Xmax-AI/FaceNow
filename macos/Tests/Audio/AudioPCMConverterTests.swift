//
//  AudioPCMConverterTests.swift
//  FaceNow
//

import XCTest
import AVFoundation
import AudioTimelineBuffer
@testable import CameraCore
@testable import VirtualMicrophoneCore

final class AudioPCMConverterTests: XCTestCase {
    func testRenderWithoutAllocatedStorageReturnsSilence() throws {
        let ring = try XCTUnwrap(AudioTimelineBufferCreate(48_000))
        defer { AudioTimelineBufferDestroy(ring) }
        var list = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: 384, mData: nil)
        )
        var stamp = AudioTimeStamp()
        stamp.mHostTime = mach_absolute_time()
        stamp.mFlags = .hostTimeValid
        var flags: AudioUnitRenderActionFlags = []
        XCTAssertEqual(
            AudioTimelineBufferRender(UnsafeMutableRawPointer(ring), &flags, &stamp, 0, 48, &list),
            noErr
        )
        XCTAssertTrue(flags.contains(.unitRenderAction_OutputIsSilence))
    }

    func testFiveSecondAudioHistoryAtEverySupportedDeviceRate() throws {
        for rate in [44_100.0, 48_000.0, 192_000.0] {
            let ring = try XCTUnwrap(AudioTimelineBufferCreate(rate))
            defer { AudioTimelineBufferDestroy(ring) }
            AudioTimelineBufferSetPlaybackDelay(ring, 5)
            let frames = UInt32(rate * 5.15)
            let stream = [Float](repeating: 0.5, count: Int(frames) * 2)
            stream.withUnsafeBufferPointer { pointer in
                AudioTimelineBufferSchedule(ring, 100, pointer.baseAddress, frames)
            }
            XCTAssertTrue(render(ring, at: 100).allSatisfy { $0 == 0 })
            let delayed = render(ring, at: 105)
            XCTAssertTrue(delayed.allSatisfy { abs($0 - 0.5) < 0.001 })
            AudioTimelineBufferReset(ring)
            XCTAssertTrue(render(ring, at: 105).allSatisfy { $0 == 0 })
        }
    }

    func testChangingDelayCrossfadesBufferedHistoryWithoutClearingIt() throws {
        let ring = try XCTUnwrap(AudioTimelineBufferCreate(48_000))
        defer { AudioTimelineBufferDestroy(ring) }
        for (time, value) in [(100.1, Float(0.2)), (100.3, Float(0.8))] {
            [Float](repeating: value, count: 8000).withUnsafeBufferPointer { pointer in
                AudioTimelineBufferSchedule(ring, time, pointer.baseAddress, 4000)
            }
        }
        XCTAssertEqual(render(ring, at: 100.3)[0], 0.8, accuracy: 0.001)
        AudioTimelineBufferSetPlaybackDelay(ring, 0.2)
        let transition = render(ring, at: 100.31, frames: 961)
        XCTAssertEqual(transition[0], 0.8, accuracy: 0.001)
        XCTAssertEqual(transition.last!, 0.2, accuracy: 0.001)
        for index in stride(from: 2, to: transition.count, by: 2) {
            XCTAssertLessThan(abs(transition[index] - transition[index - 2]), 0.001)
        }
        AudioTimelineBufferSetPlaybackDelay(ring, 0)
        let reset = render(ring, at: 100.34, frames: 961)
        XCTAssertEqual(reset[0], 0.2, accuracy: 0.001)
        XCTAssertEqual(reset.last!, 0.8, accuracy: 0.001)
        AudioTimelineBufferReset(ring)
        XCTAssertTrue(render(ring, at: 100.36).allSatisfy { $0 == 0 })
    }

    func testOutputGainAmplifiesStereoAndLimitsPeaks() throws {
        let ring = try XCTUnwrap(AudioTimelineBufferCreate(48_000))
        defer { AudioTimelineBufferDestroy(ring) }
        AudioTimelineBufferSetOutputGain(ring, 3)
        let source: [Float] = [0.25, -0.25, 0.75, -0.75]
        source.withUnsafeBufferPointer {
            AudioTimelineBufferSchedule(ring, 100, $0.baseAddress, 2)
        }
        let output = render(ring, at: 100, frames: 2)
        XCTAssertEqual(output, [0.75, -0.75, 1, -1])
        var stored = [Float](repeating: 0, count: 4)
        stored.withUnsafeMutableBufferPointer {
            XCTAssertEqual(AudioTimelineBufferRead(ring, 4_800_000, $0.baseAddress, 2), 2)
        }
        XCTAssertEqual(stored, source, "Output gain must not alter buffered source audio or direct reads")
    }

    func testVolumeChangesRampImmediatelyAcrossDelayedAudioAndCanMute() throws {
        for rate in [44_100.0, 48_000.0] {
            let ring = try XCTUnwrap(AudioTimelineBufferCreate(rate))
            defer { AudioTimelineBufferDestroy(ring) }
            AudioTimelineBufferSetPlaybackDelay(ring, 5)
            let source = [Float](repeating: 0.25, count: Int(rate) * 2)
            source.withUnsafeBufferPointer {
                AudioTimelineBufferSchedule(ring, 100, $0.baseAddress, UInt32(rate))
            }
            XCTAssertEqual(render(ring, at: 105)[0], 0.25, accuracy: 0.0001)
            AudioTimelineBufferSetOutputGain(ring, 2)
            let rampFrames = UInt32((rate * 0.02).rounded())
            let louder = render(ring, at: 105.01, frames: rampFrames + 1)
            XCTAssertEqual(louder[0], 0.25, accuracy: 0.001)
            XCTAssertEqual(louder.last!, 0.5, accuracy: 0.0001)
            for index in stride(from: 2, to: louder.count, by: 2) {
                XCTAssertGreaterThanOrEqual(louder[index], louder[index - 2])
                XCTAssertLessThan(louder[index] - louder[index - 2], 0.001)
                XCTAssertEqual(louder[index], louder[index + 1])
            }
            AudioTimelineBufferSetOutputGain(ring, 0)
            let muted = render(ring, at: 105.04, frames: rampFrames + 1)
            XCTAssertEqual(muted.last!, 0)
            XCTAssertTrue(render(ring, at: 105.07).allSatisfy { $0 == 0 })
        }
    }

    func testOutputGainRejectsNonfiniteValuesAndBoundsSavedSettings() throws {
        for (gain, expected) in [(Float.nan, Float(0.25)), (.infinity, 0.25), (-1, 0), (9, 0.75)] {
            let ring = try XCTUnwrap(AudioTimelineBufferCreate(48_000))
            defer { AudioTimelineBufferDestroy(ring) }
            AudioTimelineBufferSetOutputGain(ring, gain)
            let source = [Float](repeating: 0.25, count: 96)
            source.withUnsafeBufferPointer {
                AudioTimelineBufferSchedule(ring, 100, $0.baseAddress, 48)
            }
            XCTAssertTrue(render(ring, at: 100).allSatisfy { abs($0 - expected) < 0.0001 })
        }
    }

    private func render(
        _ ring: OpaquePointer,
        at seconds: TimeInterval,
        frames: UInt32 = 48
    ) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(frames) * 2)
        samples.withUnsafeMutableBytes { bytes in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: UInt32(bytes.count),
                    mData: bytes.baseAddress
                )
            )
            var stamp = AudioTimeStamp()
            stamp.mHostTime = AVAudioTime.hostTime(forSeconds: seconds)
            stamp.mFlags = .hostTimeValid
            var flags: AudioUnitRenderActionFlags = []
            XCTAssertEqual(
                AudioTimelineBufferRender(UnsafeMutableRawPointer(ring), &flags, &stamp, 0, frames, &list),
                noErr
            )
        }
        return samples
    }

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
