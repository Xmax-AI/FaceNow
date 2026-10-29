//
//  OnboardingRepository.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Factory
import Combine
import Foundation
#if canImport(Storage)
    import Storage
#endif

/// Owns device-preparation progress, completion preferences, and first-launch content.
@MainActor
final class OnboardingRepository: ObservableObject {

    /// The ordered preparation stages, independent of system permission APIs.
    enum Step: Int, CaseIterable {

        /// Grants physical camera access.
        case camera

        /// Installs and enables the output device.
        case virtualCamera

        /// Explains camera selection in a video calling app.
        case videoCalls

        /// The concise progress label displayed above the guide.
        var title: String {
            switch self {
            case .camera: OnboardingStrings.contentCameraAccess
            case .virtualCamera: OnboardingStrings.virtualCamera
            case .videoCalls: OnboardingStrings.contentVideoCalls
            }
        }
    }

    /// Device preparation is remembered on this Mac rather than attached to account credentials.
    @Injected(\.userDefaults) private var userDefaults: UserDefaults

    /// The current preparation stage, retained while the guide is open.
    @Published private(set) var step = Step.camera

    /// Whether the home coordinator should retain the modal guide.
    @Published private(set) var isPresented = false

    /// The latest physical-camera permission and available-device check.
    @Published private(set) var cameraReady = false

    /// The latest installed-version and output-device check.
    @Published private(set) var virtualCameraReady = false

    /// Keeps ready stages visible in order while the complete onboarding interface is being reviewed.
    private var reviewsAllSteps = false

    /// The preference written only after the video-call instructions are completed.
    var hasCompletedGuide: Bool { userDefaults.bool(forKey: "facenow.onboarding.completed.v1") }

    /// Suppresses future automatic guides after any presentation, including unfinished preparation.
    var hasShownGuide: Bool {
        userDefaults.bool(forKey: "facenow.onboarding.shown.v1") || hasCompletedGuide
    }

    /// Persists actual presentation separately from scheduling and successful preparation.
    func recordPresentation() {
        userDefaults.set(true, forKey: "facenow.onboarding.shown.v1")
    }

    /// The first unmet device requirement, followed by the video-call instructions.
    var firstIncompleteStep: Step {
        !cameraReady ? .camera : !virtualCameraReady ? .virtualCamera : .videoCalls
    }

    /// Opens the first unmet requirement or explicitly reviews every stage from camera access.
    func begin(
        at requestedStep: Step? = nil,
        fromFirstStep: Bool = false
    ) {
        reviewsAllSteps = fromFirstStep
        let requested = fromFirstStep ? .camera : requestedStep ?? firstIncompleteStep
        if !cameraReady {
            step = .camera
        } else if requested == .videoCalls, !virtualCameraReady {
            step = .virtualCamera
        } else {
            step = requested
        }
        isPresented = true
    }

    /// Advances newly completed requirements and returns to requirements that become invalid.
    func updateReadiness(
        camera: Bool,
        virtualCamera: Bool,
        cameraAccessJustGranted: Bool = false
    ) {
        let cameraChanged = cameraReady != camera
        let virtualCameraChanged = virtualCameraReady != virtualCamera
        if cameraChanged { cameraReady = camera }
        if virtualCameraChanged { virtualCameraReady = virtualCamera }
        guard isPresented else { return }
        if cameraAccessJustGranted, step == .camera {
            step = .virtualCamera
        } else if cameraChanged, !camera {
            step = .camera
        } else if virtualCameraChanged, !virtualCamera, step == .videoCalls {
            step = firstIncompleteStep
        } else if !reviewsAllSteps,
            (cameraChanged && camera && step == .camera)
                || (virtualCameraChanged && virtualCamera && step == .virtualCamera)
        {
            step = firstIncompleteStep
        }
    }

    /// Allows completed device steps to be revisited without changing their system state.
    func previous() {
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    /// Moves forward only after the current device requirement is satisfied.
    func advance() {
        switch step {
        case .camera where cameraReady:
            step = !reviewsAllSteps && virtualCameraReady ? .videoCalls : .virtualCamera
        case .virtualCamera where cameraReady && virtualCameraReady: step = .videoCalls
        default: break
        }
    }

    /// Records completion only when both devices are ready and the final guide is confirmed.
    func complete() {
        guard isPresented, step == .videoCalls, cameraReady, virtualCameraReady else { return }
        userDefaults.set(true, forKey: "facenow.onboarding.completed.v1")
        dismiss()
    }

    /// Leaves setup resumable without marking skipped requirements as completed.
    func dismiss() {
        guard isPresented else { return }
        isPresented = false
    }

    /// The headline above the initial camera stage.
    let headline = OnboardingStrings.contentBringYourNewLookIntoVideoCallingApps

    /// The service notice displayed with policy links beneath the Start Camera action.
    let serviceNotice = OnboardingStrings.contentWeAccessYourCameraInAccordanceWithOurTerms

    /// The product's terms of use.
    let termsURL = URL(string: "https://platform.xmaxai.com/docs/resources/terms")!

    /// The product's privacy policy.
    let privacyURL = URL(string: "https://platform.xmaxai.com/docs/resources/privacy")!

    /// The ownership line displayed below the stage.
    let copyright = OnboardingStrings.contentCopyright2026XMAXAIPTELTDAllRightsReserved
}

extension Container {

    /// The shared Onboarding repository registered for this container.
    @MainActor
    var onboardingRepo: Factory<OnboardingRepository> {
        Factory(self) { @MainActor in OnboardingRepository() }.singleton
    }
}
