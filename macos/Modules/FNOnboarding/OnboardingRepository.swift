//
//  OnboardingRepository.swift
//  FaceNow
//

import Factory
import Combine
import Foundation
#if canImport(FNNetwork)
    import FNNetwork
#endif
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

        /// Offers optional physical microphone access.
        case microphone

        /// Offers optional synchronized audio output through the virtual microphone.
        case virtualMicrophone

        /// Explains camera selection in a video calling app.
        case videoCalls

        /// Groups both audio pages into one optional progress stage.
        var stage: Stage {
            switch self {
            case .camera: .camera
            case .virtualCamera: .virtualCamera
            case .microphone, .virtualMicrophone: .audio
            case .videoCalls: .videoCalls
            }
        }
    }

    /// The four user-facing stages, with audio preparation grouped as an optional decision.
    enum Stage: Int, CaseIterable {

        /// Prepares the physical camera input.
        case camera

        /// Prepares virtual video output.
        case virtualCamera

        /// Prepares microphone access and synchronized audio output.
        case audio

        /// Explains how to select FaceNow in a calling app.
        case videoCalls

        /// The progress label displayed above the guide.
        var title: String {
            switch self {
            case .camera: OnboardingStrings.contentCameraAccess
            case .virtualCamera: OnboardingStrings.virtualCamera
            case .audio: OnboardingStrings.audioSetup
            case .videoCalls: OnboardingStrings.contentVideoCalls
            }
        }
    }

    /// Device preparation is remembered on this Mac rather than attached to account credentials.
    @Injected(\.userDefaults) private var userDefaults: UserDefaults

    /// Distinguishes the process requesting a relaunch from the replacement process consuming it.
    private let processID: Int32

    /// Stores the relaunch source independently of guide presentation and completion preferences.
    private static let resumeKey = "facenow.onboarding.resumeVideoCallsFromProcess.v1"

    /// The current preparation stage, retained while the guide is open.
    @Published private(set) var step = Step.camera

    /// Whether the home coordinator should retain the modal guide.
    @Published private(set) var isPresented = false

    /// The latest physical-camera permission and available-device check.
    @Published private(set) var cameraReady = false

    /// Whether the system currently permits physical microphone input.
    @Published private(set) var microphoneReady = false

    /// Whether optional microphone preparation was explicitly deferred on this Mac.
    @Published private(set) var microphoneSkipped = false

    /// Whether the virtual microphone is published, enabled, and free of output failures.
    @Published private(set) var virtualMicrophoneReady = false

    /// Whether optional audio setup was explicitly deferred on this Mac.
    @Published private(set) var virtualMicrophoneSkipped = false

    /// The latest installed-version and output-device check.
    @Published private(set) var virtualCameraReady = false

    /// Keeps ready stages visible in order while the complete onboarding interface is being reviewed.
    private var reviewsAllSteps = false

    /// Keeps explicitly requested repair pages focused until the user chooses to continue.
    private var advancesAutomatically = true

    /// The preference written only after the video-call instructions are completed.
    var hasCompletedGuide: Bool { userDefaults.bool(forKey: "facenow.onboarding.completed.v1") }

    /// Suppresses future automatic guides after any presentation, including unfinished preparation.
    var hasShownGuide: Bool {
        userDefaults.bool(forKey: "facenow.onboarding.shown.v1") || hasCompletedGuide
    }

    /// Requests the final guide after a relaunch without allowing the source process to consume it.
    var resumeStepAfterRelaunch: Step? {
        let sourceProcess = userDefaults.integer(forKey: Self.resumeKey)
        return sourceProcess > 0 && sourceProcess != Int(processID) ? .videoCalls : nil
    }

    /// The first unmet device requirement, followed by the video-call instructions.
    var firstIncompleteStep: Step {
        if !cameraReady { return .camera }
        if !virtualCameraReady { return .virtualCamera }
        if virtualMicrophoneSkipped { return .videoCalls }
        if !microphoneReady && !microphoneSkipped { return .microphone }
        if !virtualMicrophoneReady && !virtualMicrophoneSkipped { return .virtualMicrophone }
        return .videoCalls
    }

    /// The headline above the initial camera stage.
    let headline = OnboardingStrings.contentBringYourNewLookIntoVideoCallingApps

    /// The service notice displayed with policy links beneath the Start Camera action.
    let serviceNotice = OnboardingStrings.contentWeAccessYourCameraInAccordanceWithOurTerms

    /// The product's terms of use.
    let termsURL = NetworkEnvironment.current.termsURL

    /// The product's privacy policy.
    let privacyURL = NetworkEnvironment.current.privacyURL

    /// Creates progress ownership with an injectable process identity for restart recovery tests.
    init(
        processID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        self.processID = processID
        microphoneSkipped = userDefaults.bool(forKey: "facenow.onboarding.microphoneSkipped.v1")
        virtualMicrophoneSkipped = userDefaults.bool(forKey: "facenow.onboarding.virtualMicrophoneSkipped.v1")
    }

    /// Persists continuation before launching a replacement; a failed launch remains manually resumable.
    func prepareForRelaunch() {
        userDefaults.set(Int(processID), forKey: Self.resumeKey)
    }

    /// Persists actual presentation separately from scheduling and successful preparation.
    func recordPresentation() {
        userDefaults.set(true, forKey: "facenow.onboarding.shown.v1")
        if isPresented, resumeStepAfterRelaunch != nil {
            userDefaults.removeObject(forKey: Self.resumeKey)
        }
    }

    /// Opens the first unmet requirement or reviews all pages starting with camera access.
    func begin(
        at requestedStep: Step? = nil,
        fromFirstStep: Bool = false
    ) {
        reviewsAllSteps = fromFirstStep
        advancesAutomatically = !fromFirstStep && (requestedStep == nil || requestedStep == .videoCalls)
        let requested = fromFirstStep ? .camera : requestedStep ?? firstIncompleteStep
        if let requestedStep, requestedStep != .videoCalls, !fromFirstStep {
            step = requestedStep
        } else {
            step = requested.rawValue > firstIncompleteStep.rawValue ? firstIncompleteStep : requested
        }
        isPresented = true
    }

    /// Advances newly completed requirements and returns to requirements that become invalid.
    func updateReadiness(
        camera: Bool,
        microphone: Bool,
        virtualMicrophone: Bool,
        virtualCamera: Bool,
        cameraAccessJustGranted: Bool = false,
        microphoneAccessJustGranted: Bool = false
    ) {
        let cameraChanged = cameraReady != camera
        let microphoneChanged = microphoneReady != microphone
        let virtualMicrophoneChanged = virtualMicrophoneReady != virtualMicrophone
        let virtualCameraChanged = virtualCameraReady != virtualCamera
        if cameraChanged { cameraReady = camera }
        if microphoneChanged { microphoneReady = microphone }
        if virtualMicrophoneChanged { virtualMicrophoneReady = virtualMicrophone }
        if microphone, microphoneSkipped {
            microphoneSkipped = false
            userDefaults.removeObject(forKey: "facenow.onboarding.microphoneSkipped.v1")
        }
        if virtualMicrophone, virtualMicrophoneSkipped {
            virtualMicrophoneSkipped = false
            userDefaults.removeObject(forKey: "facenow.onboarding.virtualMicrophoneSkipped.v1")
        }
        if virtualCameraChanged { virtualCameraReady = virtualCamera }
        guard isPresented else { return }
        if cameraAccessJustGranted, step == .camera, advancesAutomatically || reviewsAllSteps {
            step = .virtualCamera
        } else if microphoneAccessJustGranted, step == .microphone, advancesAutomatically || reviewsAllSteps {
            step = reviewsAllSteps ? .virtualMicrophone : firstIncompleteStep
        } else if advancesAutomatically || reviewsAllSteps, firstIncompleteStep.rawValue < step.rawValue,
            (cameraChanged && !camera)
                || (microphoneChanged && !microphone && !microphoneSkipped)
                || (virtualMicrophoneChanged && !virtualMicrophone && !virtualMicrophoneSkipped)
                || (virtualCameraChanged && !virtualCamera)
        {
            step = firstIncompleteStep
        } else if advancesAutomatically,
            (cameraChanged && camera && step == .camera)
                || (microphoneChanged && microphone && step == .microphone)
                || (virtualMicrophoneChanged && virtualMicrophone && step == .virtualMicrophone)
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
        guard isSatisfied(step), step != .videoCalls else { return }
        step = reviewsAllSteps ? Step(rawValue: step.rawValue + 1) ?? .videoCalls : firstIncompleteStep
    }

    /// Defers both audio pages together without claiming device readiness or bypassing video setup.
    func skipAudio() {
        guard isPresented, step == .microphone || step == .virtualMicrophone else { return }
        microphoneSkipped = !microphoneReady
        virtualMicrophoneSkipped = true
        userDefaults.set(microphoneSkipped, forKey: "facenow.onboarding.microphoneSkipped.v1")
        userDefaults.set(true, forKey: "facenow.onboarding.virtualMicrophoneSkipped.v1")
        step = firstIncompleteStep
    }

    /// Records completion after required video preparation and both optional audio decisions.
    func complete() {
        guard isPresented, step == .videoCalls, firstIncompleteStep == .videoCalls else { return }
        userDefaults.set(true, forKey: "facenow.onboarding.completed.v1")
        dismiss()
    }

    /// Leaves setup resumable without marking skipped requirements as completed.
    func dismiss() {
        guard isPresented else { return }
        isPresented = false
    }

    /// Keeps real readiness distinct from explicit deferral when navigating optional stages.
    private func isSatisfied(
        _ step: Step
    ) -> Bool {
        switch step {
        case .microphone: microphoneReady || microphoneSkipped
        case .virtualMicrophone: virtualMicrophoneReady || virtualMicrophoneSkipped
        case .camera: cameraReady
        case .virtualCamera: virtualCameraReady
        case .videoCalls: true
        }
    }
}

extension Container {

    /// The shared Onboarding repository registered for this container.
    @MainActor
    var onboardingRepo: Factory<OnboardingRepository> {
        Factory(self) { @MainActor in OnboardingRepository() }.singleton
    }
}
