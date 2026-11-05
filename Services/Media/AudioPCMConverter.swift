// Copyright (c) 2026 XMAX.AI PTE. LTD.

import AVFoundation

/// Converts owned interleaved Int16 PCM into stereo Float32 outside the audio render callback.
/// One serial owner must call this object; discontinuities reset the resampler's history.
public final class AudioPCMConverter {

    /// The current streaming resampler, recreated when either format changes.
    private var converter: AVAudioConverter?

    /// Creates an initially unbound streaming converter.
    public init() {}

    /// Invalidates resampler history after a stream, clock, or session replacement.
    public func reset() { converter = nil }

    /// Returns resampled stereo or rejects malformed packets without accessing hardware devices.
    public func convert(
        data: Data,
        sourceRate: Int,
        channels: Int,
        samplesPerChannel: Int,
        outputRate: Double
    ) throws -> AVAudioPCMBuffer {
        guard (8_000...192_000).contains(sourceRate), (1...2).contains(channels),
            (1...19_200).contains(samplesPerChannel),
            data.count == samplesPerChannel * channels * 2,
            outputRate == 44_100 || outputRate == 48_000,
            let inputFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: Double(sourceRate),
                channels: AVAudioChannelCount(channels),
                interleaved: true
            ),
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: outputRate,
                channels: 2,
                interleaved: true
            )
        else { throw ConversionError.format }
        if converter?.inputFormat != inputFormat || converter?.outputFormat != outputFormat {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            converter?.primeMethod = .none
            if channels == 1 { converter?.channelMap = [0, 0] }
        }
        guard let converter,
            let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samplesPerChannel)),
            let output = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(ceil(Double(samplesPerChannel) * outputRate / Double(sourceRate)) + 64)
            )
        else { throw ConversionError.format }
        input.frameLength = AVAudioFrameCount(samplesPerChannel)
        _ = data.withUnsafeBytes { bytes in
            memcpy(input.mutableAudioBufferList.pointee.mBuffers.mData!, bytes.baseAddress!, data.count)
        }
        var supplied = false
        var conversionError: NSError?
        let result = converter.convert(to: output, error: &conversionError) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        if result == .error {
            if let conversionError { throw conversionError }
            throw ConversionError.format
        }
        return output
    }

    /// Reports unsupported PCM layout before creating buffers or scheduling samples.
    public enum ConversionError: Error { case format }
}
