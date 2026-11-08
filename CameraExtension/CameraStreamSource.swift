//
//  CameraStreamSource.swift
//  FaceNow
//

import CoreMediaIO
import Foundation
import os

/// Exposes negotiated source frame rates and a fixed 60 fps producer sink.
final class CameraStreamSource: NSObject, CMIOExtensionStreamSource {

    /// The system-facing stream.
    private(set) var stream: CMIOExtensionStream!

    /// The device owns this source for its entire lifetime.
    private unowned let device: CameraDeviceSource

    /// Records stream negotiation and producer-input diagnostics.
    private let logger = Logger(
        subsystem: VirtualCameraConfiguration.extensionBundleID,
        category: "Stream"
    )

    /// Whether this stream supplies consumer video or accepts host producer input.
    private let direction: CMIOExtensionStream.Direction

    /// The media formats exposed by this stream in negotiation order.
    let formats: [CMIOExtensionStreamFormat]

    /// The negotiated format determines source delivery cadence and sample duration.
    private(set) var activeFormatIndex = 0

    /// The sample duration of the currently negotiated stream format.
    var frameDuration: CMTime { formats[activeFormatIndex].minFrameDuration }

    /// The nominal samples per second derived from the negotiated frame duration.
    var frameRate: Int { Int((1 / frameDuration.seconds).rounded()) }

    /// Sink buffering is deliberately small to bound transport latency.
    var availableProperties: Set<CMIOExtensionProperty> {
        var properties: Set<CMIOExtensionProperty> = [.streamActiveFormatIndex, .streamFrameDuration]
        if direction == .sink {
            properties.formUnion([.streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup])
        }
        return properties
    }

    /// Builds either a camera consumer stream or a producer sink.
    init(
        device: CameraDeviceSource,
        direction: CMIOExtensionStream.Direction,
        formats: [CMIOExtensionStreamFormat]
    ) {
        self.device = device
        self.direction = direction
        self.formats = formats
        super.init()
        stream = CMIOExtensionStream(
            localizedName: direction == .source ? VirtualCameraConfiguration.deviceName : "FaceNow Input",
            streamID: direction == .source ? VirtualCameraConfiguration.sourceID : VirtualCameraConfiguration.sinkID,
            direction: direction,
            clockType: .hostTime,
            source: self
        )
    }

    /// Returns the fixed format and producer queue requirements.
    func streamProperties(
        forProperties properties: Set<CMIOExtensionProperty>
    ) throws -> CMIOExtensionStreamProperties {
        let values = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { values.activeFormatIndex = activeFormatIndex }
        if properties.contains(.streamFrameDuration) { values.frameDuration = frameDuration }
        if properties.contains(.streamSinkBufferQueueSize) { values.sinkBufferQueueSize = 2 }
        if properties.contains(.streamSinkBuffersRequiredForStartup) { values.sinkBuffersRequiredForStartup = 1 }
        return values
    }

    /// Rejects unsupported formats and frame rates instead of silently accepting them.
    func setStreamProperties(
        _ streamProperties: CMIOExtensionStreamProperties
    ) throws {
        var index = streamProperties.activeFormatIndex ?? activeFormatIndex
        guard formats.indices.contains(index) else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(kCMIOHardwareUnsupportedOperationError)
            )
        }
        if let duration = streamProperties.frameDuration {
            guard let matchingIndex = formats.firstIndex(where: { $0.minFrameDuration == duration }),
                streamProperties.activeFormatIndex == nil || matchingIndex == index
            else {
                throw NSError(
                    domain: NSOSStatusErrorDomain,
                    code: Int(kCMIOHardwareUnsupportedOperationError)
                )
            }
            index = matchingIndex
        }
        if activeFormatIndex != index {
            activeFormatIndex = index
            logger.notice("Negotiated virtual camera frame rate: \(self.frameRate) fps")
        }
    }

    /// Meeting apps may read the source; the sink permits one active local producer.
    func authorizedToStartStream(
        for client: CMIOExtensionClient
    ) -> Bool {
        if direction == .source {
            logger.notice(
                "Camera consumer authorized: pid=\(client.pid), signingID=\(client.signingID ?? "unknown", privacy: .public), negotiated=\(self.frameRate) fps"
            )
            return true
        }
        return device.authorizeProducer(client)
    }

    /// Starts this stream independently of its counterpart.
    func startStream() throws { try device.start(direction: direction) }

    /// Releases this stream's resources when the system stops it.
    func stopStream() throws { device.stop(direction: direction) }
}
