//
//  CameraStreamSource.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
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

    /// The stream direction and supported media formats.
    private let logger = Logger(subsystem: CameraConfiguration.extensionBundleID, category: "Stream")
    private let direction: CMIOExtensionStream.Direction
    let formats: [CMIOExtensionStreamFormat]

    /// The negotiated format determines source delivery cadence and sample duration.
    private(set) var activeFormatIndex = 0
    var frameDuration: CMTime { formats[activeFormatIndex].minFrameDuration }
    var frameRate: Int { Int((1 / frameDuration.seconds).rounded()) }

    /// Builds either a camera consumer stream or a producer sink.
    init(device: CameraDeviceSource, direction: CMIOExtensionStream.Direction, formats: [CMIOExtensionStreamFormat]) {
        self.device = device
        self.direction = direction
        self.formats = formats
        super.init()
        stream = CMIOExtensionStream(
            localizedName: direction == .source ? CameraConfiguration.deviceName : "FaceNow Input",
            streamID: direction == .source ? CameraConfiguration.sourceID : CameraConfiguration.sinkID,
            direction: direction, clockType: .hostTime, source: self
        )
    }

    /// Sink buffering is deliberately small to bound transport latency.
    var availableProperties: Set<CMIOExtensionProperty> {
        var properties: Set<CMIOExtensionProperty> = [.streamActiveFormatIndex, .streamFrameDuration]
        if direction == .sink {
            properties.formUnion([.streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup])
        }
        return properties
    }

    /// Returns the fixed format and producer queue requirements.
    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let values = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { values.activeFormatIndex = activeFormatIndex }
        if properties.contains(.streamFrameDuration) { values.frameDuration = frameDuration }
        if properties.contains(.streamSinkBufferQueueSize) { values.sinkBufferQueueSize = 2 }
        if properties.contains(.streamSinkBuffersRequiredForStartup) { values.sinkBuffersRequiredForStartup = 1 }
        return values
    }

    /// Rejects unsupported formats and frame rates instead of silently accepting them.
    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        var index = streamProperties.activeFormatIndex ?? activeFormatIndex
        guard formats.indices.contains(index) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kCMIOHardwareUnsupportedOperationError))
        }
        if let duration = streamProperties.frameDuration {
            guard let matchingIndex = formats.firstIndex(where: { $0.minFrameDuration == duration }),
                  streamProperties.activeFormatIndex == nil || matchingIndex == index else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(kCMIOHardwareUnsupportedOperationError))
            }
            index = matchingIndex
        }
        if activeFormatIndex != index {
            activeFormatIndex = index
            logger.notice("Negotiated virtual camera frame rate: \(self.frameRate) fps")
        }
    }

    /// Meeting apps may read the source; the sink permits one active local producer.
    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        if direction == .source {
            logger.notice("Camera consumer authorized: pid=\(client.pid), signingID=\(client.signingID ?? "unknown", privacy: .public), negotiated=\(self.frameRate) fps")
            return true
        }
        return device.authorizeProducer(client)
    }

    /// Starts this stream independently of its counterpart.
    func startStream() throws { try device.start(direction: direction) }

    /// Releases this stream's resources when the system stops it.
    func stopStream() throws { device.stop(direction: direction) }
}
