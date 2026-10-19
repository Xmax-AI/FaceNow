//
//  CameraConfiguration.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreMedia
import CoreVideo
import Foundation

/// The shared contract between the producer app and camera extension.
enum CameraConfiguration {
    /// The signing identifier of the only supported producer.
    static let appBundleID = "ai.xmax.camera"

    /// The bundled camera extension identifier.
    static let extensionBundleID = "ai.xmax.camera.extension"

    /// The camera name displayed in video conference applications.
    static let deviceName = "Xmax Virtual Camera"

    /// Stable identifiers keep camera selection intact across launches.
    static let deviceID = UUID(uuidString: "C1EF1269-DBA1-473B-BD21-7F3695635A01")!
    static let sourceID = UUID(uuidString: "C1EF1269-DBA1-473B-BD21-7F3695635A02")!
    static let sinkID = UUID(uuidString: "C1EF1269-DBA1-473B-BD21-7F3695635A03")!

    /// The fixed camera output format, independent of generation dimensions.
    static let width = 1280
    static let height = 720
    static let frameRate = 30
    static let pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    static let frameDuration = CMTime(value: 1, timescale: 30)

    /// The maximum frame age before replacing interrupted video with a waiting image.
    static let staleInterval: TimeInterval = 2
}
