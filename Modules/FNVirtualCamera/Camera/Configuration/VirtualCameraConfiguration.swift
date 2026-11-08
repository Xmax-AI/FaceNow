//
//  VirtualCameraConfiguration.swift
//  FaceNow
//

import CoreMedia
import CoreVideo
import Foundation
import ImageIO
#if canImport(CameraCore)
    import CameraCore
#endif

/// The shared contract between the producer app and camera extension.
enum VirtualCameraConfiguration {

    /// The domestic camera identity retained across device upgrades.
    private static let domesticDeviceID = UUID(uuidString: "C1EF1269-DBA1-473B-BD21-7F3695635A01")!

    /// The independent overseas camera identity.
    private static let overseaDeviceID = UUID(uuidString: "D0A786E1-5244-44BD-84F7-3AB5DF35CB45")!

    #if OVERSEA
        /// The host identity used for edition-specific diagnostics.
        static let appBundleID = "com.xmax.facenow.oversea"

        /// The extension belonging to this app edition.
        static let extensionBundleID = "com.xmax.meeting.camera.oversea.extension"

        /// The camera name displayed in video calling apps.
        static let deviceName = "FaceNow Virtual Camera"

        /// The stable device identity for this app edition.
        static let deviceID = overseaDeviceID

        /// The edition-specific consumer stream identity.
        static let sourceID = UUID(uuidString: "298F603A-1849-42AF-A824-25BC8844F364")!

        /// The edition-specific producer stream identity.
        static let sinkID = UUID(uuidString: "75F526F5-C39C-4119-BD8D-46841CEF1BE9")!

    #else
        /// The host identity used for edition-specific diagnostics.
        static let appBundleID = "com.xmax.facenow"

        /// The extension belonging to this app edition.
        static let extensionBundleID = "com.xmax.meeting.camera.extension"

        /// The camera name displayed in video calling apps.
        static let deviceName = "FaceNow 虚拟摄像头"

        /// The stable device identity for this app edition.
        static let deviceID = domesticDeviceID

        /// The edition-specific consumer stream identity.
        static let sourceID = UUID(uuidString: "C1EF1269-DBA1-473B-BD21-7F3695635A02")!

        /// The edition-specific producer stream identity.
        static let sinkID = UUID(uuidString: "C1EF1269-DBA1-473B-BD21-7F3695635A03")!

    #endif

    /// Loads the shared offline artwork once in either the app or camera extension bundle.
    static let waitingArtwork: CGImage? = {
        guard let url = Bundle.main.url(forResource: "FaceNowCameraPlaceholder", withExtension: "png"),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()

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

    /// Excludes both FaceNow output cameras from physical camera input selection.
    static func isFaceNowCamera(
        _ id: String
    ) -> Bool {
        [domesticDeviceID, overseaDeviceID].contains {
            id.caseInsensitiveCompare($0.uuidString) == .orderedSame
        }
    }
}
