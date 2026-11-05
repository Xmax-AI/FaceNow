import AVFoundation
import CoreVideo
import Foundation

private final class OutputObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var failure: String?

    func receive(_ result: Result<Bool, any Error>) {
        lock.lock()
        defer { lock.unlock() }
        switch result {
        case .success(let running): started = started || running
        case .failure(let error): failure = String(describing: error)
        }
    }

    func snapshot() -> (started: Bool, failure: String?) {
        lock.lock()
        defer { lock.unlock() }
        return (started, failure)
    }
}

@main
struct VirtualMicrophoneLoopbackMain {
    static func main() async {
        do {
            try await verify()
        } catch {
            FileHandle.standardError.write(Data("Microphone loopback failed: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func verify() async throws {
        let probe = MicrophoneReadProbeStart()
        var reading = true
        defer { if reading { _ = MicrophoneReadProbeFinish(probe) } }
        guard MicrophoneReadProbeStatus(probe) == 0 else {
            throw failure(
                "The virtual device is busy or the local reader could not start (\(MicrophoneReadProbeStatus(probe))). No test tone was sent."
            )
        }
        let output = VirtualMicrophoneOutput()
        let observation = OutputObservation()
        let producer = UUID()
        output.onStatus = { observation.receive($0) }
        output.setEnabled(true)
        output.reset(producer: producer)
        try await Task.sleep(for: .milliseconds(100))
        let preparation = observation.snapshot()
        guard preparation.started, preparation.failure == nil else {
            await output.stop()
            throw failure(
                "Enabled output was not prepared before the first PCM packet: \(preparation.failure ?? "not running")"
            )
        }
        let video = ScheduledFrameStore()
        video.reset(producer: producer)
        var image: CVPixelBuffer?
        let allocation = CVPixelBufferCreate(nil, 2, 2, kCVPixelFormatType_32BGRA, nil, &image)
        guard allocation == kCVReturnSuccess, let image else {
            await output.stop()
            throw failure("Could not allocate the synthetic video-clock fixture")
        }
        let clock = ContinuousClock()
        let start = clock.now
        for packet in 0..<200 {
            let sourceTime = 10 + Double(packet) * 0.01
            if packet.isMultiple(of: 2) {
                video.submit(
                    image,
                    producer: producer,
                    timestamp: sourceTime,
                    duration: 0.02,
                    now: AVAudioTime.seconds(forHostTime: mach_absolute_time())
                )
            }
            let samples = (0..<480).map { index -> Int16 in
                let position = packet * 480 + index
                return Int16(sin(Double(position) * 2 * .pi * 440 / 48_000) * 8192)
            }
            output.submit(
                data: samples.withUnsafeBytes { Data($0) },
                sourceRate: 48_000,
                channels: 1,
                samplesPerChannel: 480,
                producer: producer,
                discontinuous: packet == 0,
                presentationTime: video.presentationTime(forSourceTimestamp: sourceTime, producer: producer)
            )
            try await clock.sleep(until: start.advanced(by: .milliseconds((packet + 1) * 10)))
        }
        try await Task.sleep(for: .milliseconds(200))
        await output.stop()
        let captured = MicrophoneReadProbeFinish(probe)
        reading = false
        let rms = captured.frames > 0 ? sqrt(captured.energy / Double(captured.frames)) : 0
        guard captured.status == 0, captured.nonzero > 1000, rms > 0.02,
            captured.peak > 0.20, captured.peak < 0.30
        else {
            throw failure(
                "Actual system input did not match the synthetic tone: status=\(captured.status), samples=\(captured.frames), nonzero=\(captured.nonzero), peak=\(captured.peak), RMS=\(rms)"
            )
        }

        let staleProbe = MicrophoneReadProbeStart()
        guard MicrophoneReadProbeStatus(staleProbe) == 0 else {
            let result = MicrophoneReadProbeFinish(staleProbe)
            throw failure("Could not verify silence after stop: \(result.status)")
        }
        output.submit(
            data: [Int16](repeating: 8192, count: 480).withUnsafeBytes { Data($0) },
            sourceRate: 48_000,
            channels: 1,
            samplesPerChannel: 480,
            producer: producer,
            discontinuous: false,
            presentationTime: AVAudioTime.seconds(forHostTime: mach_absolute_time()) + 0.03
        )
        try await Task.sleep(for: .milliseconds(150))
        await output.stop()
        let stopped = MicrophoneReadProbeFinish(staleProbe)
        guard stopped.status == 0, stopped.nonzero == 0 else {
            throw failure("A stopped session replayed audio or accepted a stale producer")
        }
        let report: [String: Any] = [
            "deviceUID": VirtualMicrophoneOutput.deviceUID,
            "preparedBeforeFirstPCM": true,
            "clock": "production ScheduledFrameStore",
            "source": "synthetic 440 Hz PCM; no cloud generation or physical microphone capture",
            "packets": 200,
            "capturedSamples": captured.frames,
            "nonzeroSamples": captured.nonzero,
            "peak": captured.peak,
            "rms": rms,
            "stoppedSessionNonzeroSamples": stopped.nonzero,
            "systemHALLoopbackPassed": true,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "VirtualMicrophoneSystemLoopback", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
