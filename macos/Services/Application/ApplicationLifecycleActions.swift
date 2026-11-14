//
//  ApplicationLifecycleActions.swift
//  FaceNow
//

import AppKit

/// Performs explicit platform lifecycle commands without depending on business repositories.
@MainActor
enum ApplicationLifecycleActions {

    /// Asks Launch Services for a replacement process after the caller has released capture resources.
    static func launchReplacement() async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(
                at: Bundle.main.bundleURL,
                configuration: configuration
            ) { application, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if application != nil {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CocoaError(.executableNotLoadable))
                }
            }
        }
    }
}
