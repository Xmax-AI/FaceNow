import Foundation

/// Exercises production presentation mapping without opening devices or submitting system requests.
@main
struct CameraSetupPresentationMain {

    static func main() {
        let location = CameraOperationFailure(operation: .install, kind: .invalidLocation, diagnosticMessage: "location")
        let bundle = CameraOperationFailure(operation: .install, kind: .invalidBundle, diagnosticMessage: "bundle")
        var checks = 0

        func expect(
            _ readiness: CameraReadiness,
            action: CameraNoticeAction?,
            failure: CameraOperationFailure? = nil,
            preflight: CameraOperationFailure? = nil,
            operation: CameraOperationContext? = nil,
            locked: Bool = false,
            enabled: Bool = true,
            loading: Bool = false,
            surface: CameraNoticeSurface = .onboarding,
            message: String? = nil
        ) {
            let presentation = CameraNoticePresentation.make(
                readiness: readiness,
                operation: operation,
                failure: failure,
                actionsLocked: locked,
                surface: surface,
                installationFailure: preflight
            )
            precondition(presentation?.action == action, "Unexpected action for \(readiness): \(String(describing: presentation))")
            if let presentation {
                precondition(presentation.isEnabled == enabled, "Unexpected enablement for \(readiness)")
                precondition(presentation.isLoading == loading, "Unexpected progress for \(readiness)")
                if let message { precondition(presentation.message == message, "Unexpected copy for \(readiness)") }
            }
            checks += 1
        }

        for readiness: CameraReadiness in [
            .unavailable(.virtualCameraNotInstalled),
            .unavailable(.versionMismatch),
            .unavailable(.installationIncomplete),
        ] {
            expect(
                readiness,
                action: .revealApplication,
                preflight: location,
                message: OnboardingStrings.noticeMoveFaceNowToApplicationsToSetUpVirtualCamera
            )
            expect(readiness, action: .copyErrorDetails, preflight: bundle, message: OnboardingStrings.noticeInvalidCameraBundle)
        }
        // A failed command must remain actionable even when deferred native work masks its readiness.
        expect(.unavailable(.installationIncomplete), action: .revealApplication, failure: location)
        expect(.unavailable(.approvalRequired), action: .revealApplication, failure: location)
        expect(.ready, action: .revealApplication, failure: location)
        // A local activation prerequisite alone must not break an already working output device.
        expect(.ready, action: nil, preflight: location)
        expect(.ready, action: nil, preflight: bundle)
        expect(.unavailable(.virtualCameraDisabled), action: .openSettings(.cameraExtensions), preflight: location)
        expect(.permissionRequired(.notRequested), action: .requestCameraAccess, preflight: location)
        expect(.permissionRequired(.denied), action: .openSettings(.cameraPrivacy), preflight: location)
        expect(.unavailable(.virtualCameraNotInstalled), action: .installVirtualCamera)
        expect(.unavailable(.versionMismatch), action: .reinstallVirtualCamera)
        expect(.unavailable(.installationIncomplete), action: .installVirtualCamera)
        expect(.unavailable(.approvalRequired), action: .openSettings(.cameraExtensions))
        expect(.unavailable(.devicePublicationTimedOut), action: .openSettings(.cameraExtensions))
        expect(.unavailable(.reopenApplication), action: .restartApplication)
        for readiness: CameraReadiness in [
            .unavailable(.virtualCameraNotInstalled),
            .unavailable(.installationIncomplete),
            .unavailable(.approvalRequired),
            .checking(.extensionStatus),
        ] {
            expect(
                readiness,
                action: .checkAgain(.checkStatus),
                failure: CameraOperationFailure(operation: .checkStatus, diagnosticMessage: "timed out"),
                message: OnboardingStrings.noticeCameraStatusCheckFailed
            )
        }
        expect(
            .unavailable(.installationIncomplete),
            action: .checkAgain(.checkStatus),
            failure: CameraOperationFailure(operation: .checkStatus, diagnosticMessage: "timed out"),
            locked: true,
            enabled: false
        )
        expect(
            .checking(.installation),
            action: .retry(.install),
            preflight: location,
            operation: CameraOperationContext(kind: .install, origin: .user),
            enabled: false,
            loading: true
        )
        expect(.unavailable(.virtualCameraNotInstalled), action: .installVirtualCamera, locked: true, enabled: false)
        expect(.unavailable(.virtualCameraNotInstalled), action: .revealApplication, preflight: location, locked: true)
        expect(
            .unavailable(.installationIncomplete),
            action: .showHelp(.virtualCamera),
            preflight: location,
            surface: .banner,
            message: OnboardingStrings.noticeMoveFaceNowToApplicationsToSetUpVirtualCamera
        )
        print("Camera setup presentation: \(checks) state/action/copy checks passed")
    }
}
