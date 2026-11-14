//
//  VirtualMicrophoneStatus.swift
//  FaceNow
//

/// Combines driver availability and explicit output intent for every microphone status surface.
enum VirtualMicrophoneStatus: Equatable, Sendable {

    /// The audio driver is not installed or published.
    case notInstalled

    /// The driver is installed but macOS has not published the device.
    case pending

    /// The device is available, but the user has disabled output.
    case disabled

    /// The device is available and the user has enabled output, including before generation begins.
    case enabled

    /// Output has failed and requires explicit recovery.
    case failed

    /// Resolves device availability and user intent independently of generation or audio activity.
    static func resolve(
        driverInstalled: Bool,
        deviceAvailable: Bool,
        enabled: Bool,
        hasFailure: Bool
    ) -> VirtualMicrophoneStatus {
        if hasFailure { return .failed }
        guard deviceAvailable else { return driverInstalled ? .pending : .notInstalled }
        return enabled ? .enabled : .disabled
    }
}

/// Tracks only an explicit device check; background discovery remains silent.
enum VirtualMicrophoneDeviceCheckState: Equatable, Sendable {

    /// No user-requested check is being presented.
    case idle

    /// A shared device query is running.
    case checking

    /// The query finished and its availability facts have been published.
    case completed

    /// The query did not finish within the explicit check's time limit.
    case timedOut
}

/// Keeps audio device identities and installation paths separate between app editions.
enum VirtualMicrophoneConfiguration {

    #if OVERSEA
        /// The public microphone UID.
        static let deviceUID = "com.xmax.facenow.oversea.microphone.device"

        /// The hidden output UID used by this app edition.
        static let writerDeviceUID = "com.xmax.facenow.oversea.microphone.writer"

        /// The microphone name shown to calling apps.
        static let deviceName = "FaceNow Virtual Microphone"

        /// The name of the hidden virtual speaker endpoint.
        static let writerDeviceName = "FaceNow Virtual Speaker"

        /// The installed audio plug-in identifier.
        static let driverBundleID = "com.xmax.facenow.oversea.microphone.driver"

        /// The edition-specific installed driver bundle.
        static let driverFilename = "FaceNowMicrophoneOversea.driver"

    #else
        /// The public microphone UID.
        static let deviceUID = "com.xmax.facenow.microphone.device"

        /// The hidden output UID used by this app edition.
        static let writerDeviceUID = "com.xmax.facenow.microphone.writer"

        /// The microphone name shown to calling apps.
        static let deviceName = "FaceNow 虚拟麦克风"

        /// The name of the hidden virtual speaker endpoint.
        static let writerDeviceName = "FaceNow 虚拟扬声器"

        /// The installed audio plug-in identifier.
        static let driverBundleID = "com.xmax.facenow.microphone.driver"

        /// The edition-specific installed driver bundle.
        static let driverFilename = "FaceNowMicrophone.driver"

    #endif

    /// The Info.plist checked before offering driver installation.
    static let installedInfoPath = "/Library/Audio/Plug-Ins/HAL/\(driverFilename)/Contents/Info.plist"
}
