//
//  CameraStreamSource.swift
//  FaceNow
//

import CoreMediaIO
import Foundation
import os

/// Exposes the camera resolutions with separate source and producer cadences.
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

    /// The media description currently accepted or emitted by this stream.
    var activeFormat: CMIOExtensionStreamFormat { formats[activeFormatIndex] }

    /// The sample duration of the currently negotiated stream format.
    var frameDuration: CMTime { activeFormat.minFrameDuration }

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

    /// Returns the active format and producer queue requirements.
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
        let requestedIndex = streamProperties.activeFormatIndex
        var index = requestedIndex ?? activeFormatIndex
        guard formats.indices.contains(index) else {
            throw Self.unsupportedFormat
        }
        if let duration = streamProperties.frameDuration {
            let description = formats[index].formatDescription
            guard let matchingIndex = formatIndex(for: description, duration: duration),
                requestedIndex == nil || matchingIndex == index
            else { throw Self.unsupportedFormat }
            index = matchingIndex
        }
        try device.selectFormat(index, for: direction)
    }

    /// Finds the entry for a given media description and cadence.
    func formatIndex(
        for description: CMFormatDescription,
        duration: CMTime
    ) -> Int? {
        formats.firstIndex {
            CMFormatDescriptionEqual($0.formatDescription, otherFormatDescription: description)
                && $0.minFrameDuration == duration
        }
    }

    /// Publishes a new format after the device has prepared its output canvas.
    func activateFormat(
        _ index: Int,
        notify: Bool
    ) {
        guard activeFormatIndex != index else { return }
        activeFormatIndex = index
        let dimensions = CMVideoFormatDescriptionGetDimensions(activeFormat.formatDescription)
        logger.notice("Virtual camera format: \(dimensions.width)x\(dimensions.height) at \(self.frameRate) fps")
        if notify {
            let properties = CMIOExtensionStreamProperties(dictionary: [:])
            properties.activeFormatIndex = index
            stream.notifyPropertiesChanged(properties.propertiesDictionary)
        }
    }

    /// The request is outside the stream's currently supported format and cadence.
    static var unsupportedFormat: NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(kCMIOHardwareUnsupportedOperationError))
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
