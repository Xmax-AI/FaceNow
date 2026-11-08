//
//  VirtualMicrophoneOutput.swift
//  FaceNow
//

@preconcurrency import AVFoundation
import AudioUnit
import CoreAudio
import Foundation
import os
#if canImport(AudioTimelineBuffer)
    import AudioTimelineBuffer
#endif
#if canImport(CameraCore)
    import CameraCore
#endif

/// Serializes device and converter ownership; only the C ring crosses into the realtime callback.
final class VirtualMicrophoneOutput: @unchecked Sendable {

    /// Stable identity for this app edition, preserved across driver upgrades.
    static let deviceUID = VirtualMicrophoneConfiguration.deviceUID

    /// The hidden output endpoint used only to deliver generated audio to the public microphone.
    static let writerDeviceUID = VirtualMicrophoneConfiguration.writerDeviceUID

    /// Retains native failure codes for troubleshooting without exposing PCM or account data.
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.xmax.facenow",
        category: "VirtualMicrophone"
    )

    /// Owns format conversion, lifecycle changes, and all non-realtime work.
    private let worker = DispatchQueue(label: "ai.xmax.microphone.output", qos: .userInitiated)

    /// Bounds retained packets before dispatching format conversion to the worker.
    private let pendingLock = NSLock()
    private var pendingCount = 0
    private var lostPackets = false

    /// Aggregates admission and scheduling without retaining PCM in diagnostic output.
    private struct Statistics {
        /// PCM packets entering the application output, before admission checks.
        var received = 0
        /// Packets copied into the current device's playback timeline.
        var scheduled = 0
        /// Converted sample frames scheduled in each stereo channel.
        var frames = 0
        /// The largest absolute scheduled sample value, without retaining audio content.
        var peak: Float = 0
        /// Packets rejected because their PCM format or byte count is invalid.
        var invalid = 0
        /// Packets rejected by the bounded worker queue.
        var overflow = 0
        /// Packets belonging to a stopped, disabled, or replaced producer.
        var inactive = 0
        /// Packets without a current video-clock mapping.
        var unmapped = 0
        /// Packets whose playback deadline has expired.
        var late = 0
        /// Packets whose playback deadline exceeds the scheduling window.
        var future = 0
    }

    /// Uses the admission lock because SDK delivery and transport work update different counters.
    private var statistics = Statistics()

    /// Reports idle input as well as active scheduling during an enabled generation session.
    private var statisticsTimer: DispatchSourceTimer?

    /// Rejects packets from a previous generation session on the worker.
    private var producer: UUID?
    private var enabled = false
    private var unit: AudioUnit?
    private var ring: OpaquePointer?
    private var sampleRate: Double = 48_000
    private var device: AudioDeviceID = 0
    private let converter = AudioPCMConverter()
    private var nextPresentationTime: TimeInterval?

    /// The additional playback hold in seconds, independent of automatic timestamp placement.
    private var playbackDelay: TimeInterval = 0

    /// Publishes transport state without invoking UI from the realtime callback.
    var onStatus: (@Sendable (Result<Bool, Error>) -> Void)?

    /// Returns the installed device by immutable UID without changing the system defaults.
    static func installedDevice() -> AudioDeviceID? {
        device(withUID: deviceUID)
    }

    /// Uses the hidden writer, retaining compatibility until an installed duplex driver is upgraded.
    static func installedWriterDevice() -> AudioDeviceID? {
        if let writer = device(withUID: writerDeviceUID) { return writer }
        guard let legacy = installedDevice() else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(legacy, &address, 0, nil, &size) == noErr,
            size > 0
        else { return nil }
        return legacy
    }

    /// Resolves hidden devices through the system UID translation API instead of normal enumeration.
    private static func device(
        withUID identifier: String
    ) -> AudioDeviceID? {
        var uid: CFString = identifier as CFString
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var result: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                pointer,
                &size,
                &result
            )
        }
        return status == noErr && result != kAudioObjectUnknown ? result : nil
    }

    /// Updates the generation identity and explicitly invalidates queued audio on the worker.
    func reset(
        producer: UUID?,
        playbackDelay: TimeInterval = 0
    ) {
        worker.async { [self] in
            stopStatistics()
            stopUnit()
            self.producer = producer
            self.playbackDelay = playbackDelay.isFinite ? min(5, max(0, playbackDelay)) : 0
            prepareOutput()
        }
    }

    /// Adjusts the render read position while retaining buffered audio and rejecting old sessions.
    func setPlaybackDelay(
        _ delay: TimeInterval,
        producer: UUID
    ) {
        worker.async { [self] in
            guard self.producer == producer else { return }
            playbackDelay = delay.isFinite ? min(5, max(0, delay)) : 0
            AudioTimelineBufferSetPlaybackDelay(ring, playbackDelay)
        }
    }

    /// Changes the saved output intent independently of SDK playback volume and microphone capture.
    func setEnabled(
        _ enabled: Bool
    ) {
        worker.async { [self] in
            self.enabled = enabled
            if enabled {
                prepareOutput()
            } else {
                stopStatistics()
                stopUnit()
            }
        }
    }

    /// Copies owned PCM through a bounded queue; stale lifecycle or excessively late packets are dropped.
    func submit(
        data: Data,
        sourceRate: Int,
        channels: Int,
        samplesPerChannel: Int,
        producer: UUID,
        discontinuous: Bool,
        presentationTime: TimeInterval?
    ) {
        let valid =
            (8_000...192_000).contains(sourceRate) && (1...2).contains(channels)
            && (1...19_200).contains(samplesPerChannel) && data.count == samplesPerChannel * channels * 2
        pendingLock.lock()
        statistics.received += 1
        guard valid else {
            statistics.invalid += 1
            pendingLock.unlock()
            return
        }
        guard pendingCount < 8 else {
            lostPackets = true
            statistics.overflow += 1
            pendingLock.unlock()
            return
        }
        let resetsTimeline = discontinuous || lostPackets
        lostPackets = false
        pendingCount += 1
        pendingLock.unlock()
        worker.async { [self] in
            defer {
                pendingLock.lock()
                pendingCount -= 1
                pendingLock.unlock()
            }
            guard self.producer == producer, enabled else {
                record { $0.inactive += 1 }
                return
            }
            guard let presentationTime, presentationTime.isFinite else {
                record { $0.unmapped += 1 }
                return
            }
            let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
            guard presentationTime >= now - 0.08 else {
                record { $0.late += 1 }
                return
            }
            guard presentationTime <= now + 0.15 else {
                record { $0.future += 1 }
                return
            }
            do {
                try startUnitIfNeeded()
                guard let ring else { return }
                if resetsTimeline {
                    AudioTimelineBufferReset(ring)
                    nextPresentationTime = nil
                    converter.reset()
                }
                let output = try converter.convert(
                    data: data,
                    sourceRate: sourceRate,
                    channels: channels,
                    samplesPerChannel: samplesPerChannel,
                    outputRate: sampleRate
                )
                guard output.frameLength > 0, let samples = output.floatChannelData?[0] else { return }
                // The driver's read side adds 512 frames. Preserve contiguous sample placement across packets.
                let target = presentationTime - 512 / sampleRate
                let due = nextPresentationTime.flatMap { abs($0 - target) < 0.003 ? $0 : nil } ?? target
                AudioTimelineBufferSchedule(ring, due, samples, output.frameLength)
                nextPresentationTime = due + Double(output.frameLength) / sampleRate
                var peak: Float = 0
                for index in 0..<(Int(output.frameLength) * 2) { peak = max(peak, abs(samples[index])) }
                record {
                    $0.scheduled += 1
                    $0.frames += Int(output.frameLength)
                    $0.peak = max($0.peak, peak)
                }
            } catch {
                failOutput(error)
            }
        }
    }

    /// Waits for callback teardown before releasing the ring or returning from session cleanup.
    func stop() async {
        await withCheckedContinuation { continuation in
            worker.async { [self] in
                stopStatistics()
                stopUnit()
                producer = nil
                continuation.resume()
            }
        }
    }

    /// Opens the enabled session's endpoint before the first PCM packet, leaving idle samples silent.
    private func prepareOutput() {
        guard enabled, producer != nil else { return }
        do {
            try startUnitIfNeeded()
            guard statisticsTimer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: worker)
            timer.schedule(deadline: .now() + 5, repeating: 5)
            timer.setEventHandler { [weak self] in self?.reportStatistics() }
            statisticsTimer = timer
            timer.resume()
        } catch {
            failOutput(error)
        }
    }

    /// Updates metadata only; audio samples never enter diagnostics.
    private func record(
        _ update: (inout Statistics) -> Void
    ) {
        pendingLock.lock()
        update(&statistics)
        pendingLock.unlock()
    }

    /// Separates absent SDK audio, clock rejection, and successfully scheduled output.
    private func reportStatistics() {
        pendingLock.lock()
        let values = statistics
        statistics = Statistics()
        pendingLock.unlock()
        logger.notice(
            "Virtual microphone packets: received=\(values.received), scheduled=\(values.scheduled), frames=\(values.frames), peak=\(values.peak), unmapped=\(values.unmapped), late=\(values.late), future=\(values.future), invalid=\(values.invalid), overflow=\(values.overflow), inactive=\(values.inactive), running=\(self.unit != nil)"
        )
    }

    /// Flushes the final interval before session replacement or explicit disablement.
    private func stopStatistics() {
        guard let timer = statisticsTimer else { return }
        timer.cancel()
        statisticsTimer = nil
        reportStatistics()
    }

    /// Preserves a nonfatal error while releasing the endpoint and preventing repeated starts.
    private func failOutput(
        _ error: any Error
    ) {
        logger.error("Virtual microphone output failed: \(String(describing: error), privacy: .public)")
        stopStatistics()
        stopUnit()
        enabled = false
        onStatus?(.failure(error))
    }

    /// Attaches AUHAL only to FaceNow's device, with no microphone input bus or default-device mutation.
    private func startUnitIfNeeded() throws {
        if let unit {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var current: Double = 0
            var size = UInt32(MemoryLayout<Double>.size)
            let result = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &current)
            if result == noErr && current == sampleRate { return }
            _ = unit
            stopUnit()
        }
        guard let device = Self.installedWriterDevice() else { throw OutputError.notInstalled }
        self.device = device
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Double>.size)
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &sampleRate))
        guard sampleRate == 44_100 || sampleRate == 48_000 else { throw OutputError.format }
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else { throw OutputError.format }
        var instance: AudioComponentInstance?
        try check(AudioComponentInstanceNew(component, &instance))
        guard let instance else { throw OutputError.format }
        unit = instance
        do {
            var off: UInt32 = 0
            var on: UInt32 = 1
            var selectedDevice = device
            try check(
                AudioUnitSetProperty(instance, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &off, 4)
            )
            try check(
                AudioUnitSetProperty(instance, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &on, 4)
            )
            try check(
                AudioUnitSetProperty(
                    instance,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &selectedDevice,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
            )
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 2,
                interleaved: true
            )!
            var asbd = format.streamDescription.pointee
            try check(
                AudioUnitSetProperty(
                    instance,
                    kAudioUnitProperty_StreamFormat,
                    kAudioUnitScope_Input,
                    0,
                    &asbd,
                    UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                )
            )
            guard let ring = AudioTimelineBufferCreate(sampleRate) else { throw OutputError.format }
            self.ring = ring
            AudioTimelineBufferSetPlaybackDelay(ring, playbackDelay)
            var callback = AURenderCallbackStruct(
                inputProc: AudioTimelineBufferRender,
                inputProcRefCon: UnsafeMutableRawPointer(ring)
            )
            try check(
                AudioUnitSetProperty(
                    instance,
                    kAudioUnitProperty_SetRenderCallback,
                    kAudioUnitScope_Input,
                    0,
                    &callback,
                    UInt32(MemoryLayout<AURenderCallbackStruct>.size)
                )
            )
            try check(AudioUnitInitialize(instance))
            try check(AudioOutputUnitStart(instance))
            logger.notice("Virtual microphone output started: device=\(device), sampleRate=\(self.sampleRate)")
            onStatus?(.success(true))
        } catch {
            stopUnit()
            throw error
        }
    }

    /// Stops callbacks before freeing their context; delayed SDK packets cannot restart a stopped session.
    private func stopUnit() {
        if let unit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
        unit = nil
        if let ring { AudioTimelineBufferDestroy(ring) }
        ring = nil
        converter.reset()
        nextPresentationTime = nil
        onStatus?(.success(false))
    }

    /// Preserves the native Core Audio failure for the localized presentation layer.
    private func check(
        _ status: OSStatus
    ) throws {
        if status != noErr { throw OutputError.coreAudio(status) }
    }

    /// Describes output preparation failures independently of generation or video transport.
    enum OutputError: Error {
        case notInstalled
        case format
        case coreAudio(OSStatus)
    }
}
