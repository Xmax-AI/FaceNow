//
//  VirtualCameraConfiguration.swift
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
#if canImport(CameraCore)
    import CameraCore
#endif

/// The shared contract between the producer app and camera extension.
enum VirtualCameraConfiguration {

    /// The signing identifier of the only supported producer.
    static let appBundleID = "com.xmax.meeting.camera"

    /// The bundled camera extension identifier.
    static let extensionBundleID = "com.xmax.meeting.camera.extension"

    /// The camera name displayed in video conference applications.
    static let deviceName = "FaceNow - Xmax Virtual Camera"

    /// Stable identifiers keep camera selection intact across launches.
    static let deviceID = UUID(uuidString: "C1EF1269-DBA1-473B-BD21-7F3695635A01")!

    /// The stable source-stream identifier retained across application upgrades.
    static let sourceID = UUID(uuidString: "C1EF1269-DBA1-473B-BD21-7F3695635A02")!

    /// The stable producer-sink identifier retained across application upgrades.
    static let sinkID = UUID(uuidString: "C1EF1269-DBA1-473B-BD21-7F3695635A03")!

    /// The fixed camera format supplied to generic renderers by the owning module.
    static let videoFormat = VideoFormat(
        width: 1920,
        height: 1080,
        frameRate: 60,
        pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    )

    /// The camera canvas width in pixels.
    static var width: Int { videoFormat.width }

    /// The camera canvas height in pixels.
    static var height: Int { videoFormat.height }

    /// The preferred producer cadence in samples per second.
    static var frameRate: Int { videoFormat.frameRate }

    /// The negotiated video-range NV12 representation.
    static var pixelFormat: OSType { videoFormat.pixelFormat }

    /// The preferred producer sample duration.
    static var frameDuration: CMTime { videoFormat.frameDuration }

    /// Source formats retain 30 fps compatibility while preferring 60 fps.
    static let sourceFrameRates = [60, 30]

    /// The maximum frame age before replacing interrupted video with a waiting image.
    static let staleInterval: TimeInterval = 2
}
