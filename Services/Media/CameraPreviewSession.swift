//
//  CameraPreviewSession.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import AVFoundation
import Foundation

/// Owns video-only capture; all configuration and blocking start/stop work runs on one serial queue.
final class CameraPreviewSession: @unchecked Sendable {

    /// The stable session exposed only for binding an AVFoundation preview layer.
    let session = AVCaptureSession()

    /// Serializes capture mutations so a stop always drains previously requested startup work.
    private let queue = DispatchQueue(label: "ai.xmax.camera-preview")

    /// Explains camera availability failures without exposing capture internals to the UI.
    enum Failure: LocalizedError {

        /// The user has not granted video access.
        case permissionDenied

        /// No usable physical input is available.
        case unavailable

        /// AVFoundation could not begin video capture.
        case startFailed

        /// The message displayed through the existing home toast.
        var errorDescription: String? {
            switch self {
            case .permissionDenied: "Allow camera access in System Settings to preview."
            case .unavailable: "Connect a camera and select it to preview."
            case .startFailed: "Unable to open the camera. Check whether another app is using it, then try again."
            }
        }
    }

    /// Opens the selected input, or the system default when device selection is not yet available.
    @MainActor
    func start(
        deviceID: String,
        excludedDeviceID: String,
        excludedDeviceName: String
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                        throw Failure.permissionDenied
                    }
                    let device =
                        deviceID.isEmpty
                        ? AVCaptureDevice.default(for: .video) : AVCaptureDevice(uniqueID: deviceID)
                    guard let device, device.uniqueID != excludedDeviceID,
                        device.localizedName != excludedDeviceName
                    else { throw Failure.unavailable }
                    let input = try AVCaptureDeviceInput(device: device)
                    session.beginConfiguration()
                    session.inputs.forEach(session.removeInput)
                    if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
                    guard session.canAddInput(input) else {
                        session.commitConfiguration()
                        throw Failure.unavailable
                    }
                    session.addInput(input)
                    session.commitConfiguration()
                    session.startRunning()
                    guard session.isRunning else { throw Failure.startFailed }
                    continuation.resume()
                } catch {
                    session.stopRunning()
                    session.inputs.forEach(session.removeInput)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Releases the physical device after all earlier capture work has finished.
    @MainActor
    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                session.stopRunning()
                session.beginConfiguration()
                session.inputs.forEach(session.removeInput)
                session.commitConfiguration()
                continuation.resume()
            }
        }
    }
}
