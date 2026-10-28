//
//  CameraStatusViewModel.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Factory

/// Projects shared camera facts and validates typed notice commands before execution.
@MainActor
final class CameraStatusViewModel {

    /// Owns camera authorization, extension operations, and device checks.
    @Injected(\.virtualCameraRepo) private var virtualCameraRepo: VirtualCameraRepository

    /// Supplies current device selection and mutation restrictions.
    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    /// The read-only status of virtual output, independent of physical input permission.
    enum VirtualCameraIndicator: Equatable {
        case available
        case checking
        case unavailable

        /// Describes the light without relying on color alone.
        var helpText: String {
            switch self {
            case .available: OnboardingStrings.landingVirtualCameraAvailable
            case .checking: OnboardingStrings.landingVirtualCameraChecking
            case .unavailable: OnboardingStrings.landingVirtualCameraUnavailable
            }
        }
    }

    /// Projects the existing virtual-output facts without creating another readiness cache.
    var virtualCameraIndicator: VirtualCameraIndicator {
        switch virtualCameraRepo.readiness(for: .virtualOutput) {
        case .ready: .available
        case .checking: .checking
        case .permissionRequired, .unavailable: .unavailable
        }
    }

    /// Derives presentation without retaining another copy of readiness or loading state.
    var presentation: CameraNoticePresentation? {
        presentation(for: .complete)
    }

    /// Uses the same mapper for a scoped guide stage and the combined home notice.
    func presentation(
        for scope: CameraPreparationScope,
        surface: CameraNoticeSurface = .banner
    ) -> CameraNoticePresentation? {
        let operation = virtualCameraRepo.operation.flatMap { $0.kind.belongs(to: scope) ? $0 : nil }
        let failure = virtualCameraRepo.operationFailure.flatMap { $0.operation.belongs(to: scope) ? $0 : nil }
        guard
            var presentation = CameraNoticePresentation.make(
                readiness: virtualCameraRepo.readiness(for: scope),
                operation: operation,
                failure: failure,
                actionsLocked: generationRepo.settingsLocked || generationRepo.isClosing,
                surface: surface
            )
        else { return nil }
        if let operation = presentation.action.operation, !presentation.isLoading {
            presentation.isEnabled = presentation.isEnabled && virtualCameraRepo.canPerform(operation)
        }
        return presentation
    }

    /// Executes device commands or returns navigation intents after checking current state again.
    func perform(
        _ action: CameraNoticeAction,
        scope: CameraPreparationScope = .complete,
        surface: CameraNoticeSurface = .banner
    ) async -> CameraNoticeAction? {
        virtualCameraRepo.synchronizeReadiness()
        guard let current = presentation(for: scope, surface: surface), current.isEnabled, !current.isLoading,
            current.action == action
        else { return nil }
        guard let operation = action.operation else { return action }
        await virtualCameraRepo.perform(operation)
        generationRepo.refreshCameras()
        return nil
    }
}
