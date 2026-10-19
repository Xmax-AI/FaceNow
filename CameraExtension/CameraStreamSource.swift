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

/// Exposes one fixed-format source or sink and delegates lifecycle to the device.
final class CameraStreamSource: NSObject, CMIOExtensionStreamSource {
    /// The system-facing stream.
    private(set) var stream: CMIOExtensionStream!

    /// The device owns this source for its entire lifetime.
    private unowned let device: CameraDeviceSource

    /// The stream direction and single supported media format.
    private let direction: CMIOExtensionStream.Direction
    let formats: [CMIOExtensionStreamFormat]

    /// This camera intentionally exposes a single fixed format.
    var activeFormatIndex = 0

    /// Builds either a camera consumer stream or a producer sink.
    init(device: CameraDeviceSource, direction: CMIOExtensionStream.Direction, format: CMIOExtensionStreamFormat) {
        self.device = device
        self.direction = direction
        formats = [format]
        super.init()
        stream = CMIOExtensionStream(
            localizedName: direction == .source ? CameraConfiguration.deviceName : "Xmax Camera Input",
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
        if properties.contains(.streamActiveFormatIndex) { values.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) { values.frameDuration = CameraConfiguration.frameDuration }
        if properties.contains(.streamSinkBufferQueueSize) { values.sinkBufferQueueSize = 2 }
        if properties.contains(.streamSinkBuffersRequiredForStartup) { values.sinkBuffersRequiredForStartup = 1 }
        return values
    }

    /// Rejects unsupported formats and frame rates instead of silently accepting them.
    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let index = streamProperties.activeFormatIndex, index != 0 {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kCMIOHardwareUnsupportedOperationError))
        }
        if let duration = streamProperties.frameDuration, duration != CameraConfiguration.frameDuration {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kCMIOHardwareUnsupportedOperationError))
        }
    }

    /// Meeting apps may read the source; only the signed host may write to the sink.
    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        direction == .source || device.authorizeProducer(client)
    }

    /// Starts this stream independently of its counterpart.
    func startStream() throws { try device.start(direction: direction) }

    /// Releases this stream's resources when the system stops it.
    func stopStream() throws { device.stop(direction: direction) }
}
