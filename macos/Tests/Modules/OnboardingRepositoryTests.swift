import Factory
import Foundation
import XCTest
@testable import FNOnboarding

@MainActor
final class OnboardingRepositoryTests: XCTestCase {

    func testExplicitVirtualCameraRepairDoesNotRedirectToUnansweredAudioSteps() {
        withRepository { _, _ in
            let repository = OnboardingRepository()
            repository.begin(at: .virtualCamera)
            repository.updateReadiness(camera: false, microphone: false, virtualMicrophone: false, virtualCamera: true)
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.complete()
            XCTAssertFalse(repository.hasCompletedGuide)
            repository.advance()
            XCTAssertEqual(repository.step, .camera)
        }
    }

    func testExplicitPermissionRepairKeepsItsResultVisibleUntilContinue() {
        withRepository { repository, _ in
            repository.begin(at: .camera)
            repository.updateReadiness(
                camera: true,
                microphone: true,
                virtualMicrophone: true,
                virtualCamera: false,
                cameraAccessJustGranted: true
            )
            XCTAssertEqual(repository.step, .camera)
            repository.advance()
            XCTAssertEqual(repository.step, .virtualCamera)
        }
    }

    func testFinalInstructionsStillRequireAllDecisionsAfterFocusedRepair() {
        withRepository { _, _ in
            let repository = OnboardingRepository()
            repository.begin(at: .virtualCamera)
            repository.dismiss()
            repository.begin(at: .videoCalls)
            XCTAssertEqual(repository.step, .camera)
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true)
            XCTAssertEqual(repository.step, .videoCalls)
        }
    }

    func testRelaunchContinuationSurvivesTheSourceProcessAndIsConsumedOnlyAfterPresentation() {
        withRepository { _, _ in
            let source = OnboardingRepository(processID: 101)
            source.begin()
            source.recordPresentation()
            source.prepareForRelaunch()
            XCTAssertNil(source.resumeStepAfterRelaunch)
            source.recordPresentation()
            XCTAssertNil(source.resumeStepAfterRelaunch)

            let replacement = OnboardingRepository(processID: 202)
            XCTAssertTrue(replacement.hasShownGuide)
            XCTAssertEqual(replacement.resumeStepAfterRelaunch, .videoCalls)
            replacement.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true)
            replacement.begin(at: replacement.resumeStepAfterRelaunch)
            XCTAssertEqual(replacement.step, .videoCalls)
            XCTAssertEqual(replacement.resumeStepAfterRelaunch, .videoCalls)
            replacement.recordPresentation()
            XCTAssertNil(replacement.resumeStepAfterRelaunch)
            XCTAssertNil(OnboardingRepository(processID: 303).resumeStepAfterRelaunch)
            XCTAssertFalse(replacement.hasCompletedGuide)
        }
    }

    func testRelaunchContinuationDoesNotSkipAnUnavailableVirtualCamera() {
        withRepository { _, _ in
            OnboardingRepository(processID: 101).prepareForRelaunch()
            let replacement = OnboardingRepository(processID: 202)
            replacement.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: false)
            replacement.begin(at: replacement.resumeStepAfterRelaunch)
            XCTAssertEqual(replacement.step, .virtualCamera)
            replacement.recordPresentation()
            replacement.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true)
            XCTAssertEqual(replacement.step, .videoCalls)
            XCTAssertFalse(replacement.hasCompletedGuide)
        }
    }

    func testRelaunchContinuationStillRequiresCameraPermission() {
        withRepository { _, _ in
            OnboardingRepository(processID: 101).prepareForRelaunch()
            let replacement = OnboardingRepository(processID: 202)
            replacement.updateReadiness(camera: false, microphone: true, virtualMicrophone: true, virtualCamera: true)
            replacement.begin(at: replacement.resumeStepAfterRelaunch)
            XCTAssertEqual(replacement.step, .camera)
            XCTAssertFalse(replacement.hasCompletedGuide)
        }
    }

    func testCancelledPresentationLeavesRelaunchContinuationForAManualReopen() {
        withRepository { _, _ in
            let source = OnboardingRepository(processID: 101)
            source.prepareForRelaunch()
            XCTAssertFalse(source.hasShownGuide)
            let replacement = OnboardingRepository(processID: 202)
            replacement.begin(at: replacement.resumeStepAfterRelaunch)
            replacement.dismiss()
            XCTAssertEqual(replacement.resumeStepAfterRelaunch, .videoCalls)
            let manuallyReopened = OnboardingRepository(processID: 303)
            manuallyReopened.recordPresentation()
            XCTAssertEqual(manuallyReopened.resumeStepAfterRelaunch, .videoCalls)
        }
    }

    func testRelaunchContinuationCanReviewACompletedGuideWithoutResettingCompletion() {
        withRepository { _, defaults in
            defaults.set(true, forKey: "facenow.onboarding.completed.v1")
            OnboardingRepository(processID: 101).prepareForRelaunch()
            let replacement = OnboardingRepository(processID: 202)
            XCTAssertTrue(replacement.hasCompletedGuide)
            replacement.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true)
            replacement.begin(at: replacement.resumeStepAfterRelaunch)
            XCTAssertEqual(replacement.step, .videoCalls)
            replacement.recordPresentation()
            replacement.dismiss()
            XCTAssertTrue(replacement.hasCompletedGuide)
            XCTAssertNil(replacement.resumeStepAfterRelaunch)
        }
    }

    func testPreparationResumesAtTheFirstMissingDeviceStep() {
        withRepository { repository, _ in
            repository.begin()
            XCTAssertEqual(repository.step, .camera)
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: false)
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.dismiss()
            XCTAssertFalse(repository.hasCompletedGuide)
            repository.begin()
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true)
            XCTAssertEqual(repository.step, .videoCalls)
            repository.dismiss()
            repository.begin()
            XCTAssertEqual(repository.step, .videoCalls)
            XCTAssertFalse(repository.hasCompletedGuide)
        }
    }

    func testCompletedDeviceSettingsAreSkippedOnEntry() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true)
            repository.begin()
            XCTAssertEqual(repository.step, .videoCalls)
            XCTAssertTrue(repository.isPresented)
        }
    }

    func testCompletionPersistsOnlyAfterFinalConfirmationWithReadyDevices() {
        withRepository { repository, _ in
            repository.begin()
            repository.complete()
            XCTAssertFalse(repository.hasCompletedGuide)
            XCTAssertTrue(repository.isPresented)
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: false)
            repository.complete()
            XCTAssertFalse(repository.hasCompletedGuide)
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true)
            repository.complete()
            XCTAssertTrue(repository.hasCompletedGuide)
            XCTAssertFalse(repository.isPresented)
            let reopened = OnboardingRepository()
            XCTAssertTrue(reopened.hasCompletedGuide)
            reopened.updateReadiness(camera: false, microphone: true, virtualMicrophone: true, virtualCamera: true)
            reopened.begin()
            XCTAssertEqual(reopened.step, .camera)
        }
    }

    func testPermissionOrOutputLossReturnsToTheMissingRequirement() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true)
            repository.begin()
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: false)
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.updateReadiness(camera: false, microphone: true, virtualMicrophone: true, virtualCamera: false)
            XCTAssertEqual(repository.step, .camera)
            repository.advance()
            XCTAssertEqual(repository.step, .camera)
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: false)
            XCTAssertEqual(repository.step, .virtualCamera)
        }
    }

    func testRevisitedReadyStepDoesNotAdvanceUntilTheUserContinues() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true)
            repository.begin()
            for expected: OnboardingRepository.Step in [.virtualMicrophone, .microphone, .virtualCamera, .camera] {
                repository.previous()
                XCTAssertEqual(repository.step, expected)
                repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true)
                XCTAssertEqual(repository.step, expected)
            }
            repository.advance()
            XCTAssertEqual(repository.step, .videoCalls)
        }
    }

    func testRequestedRepairStepAndDeferralDoNotOverwriteCompletion() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true)
            repository.begin()
            repository.complete()
            repository.begin(at: .virtualCamera)
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.dismiss()
            XCTAssertTrue(repository.hasCompletedGuide)
        }
    }

    func testDeferredFinalStepCannotBeCompletedByALateAction() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true)
            repository.begin()
            repository.dismiss()
            repository.complete()
            XCTAssertFalse(repository.hasCompletedGuide)
        }
    }

    func testShownGuidePersistsWithoutCompletingPreparation() {
        withRepository { repository, _ in
            XCTAssertFalse(repository.hasShownGuide)
            repository.begin()
            repository.recordPresentation()
            repository.dismiss()
            XCTAssertTrue(repository.hasShownGuide)
            XCTAssertFalse(repository.hasCompletedGuide)
            let reopened = OnboardingRepository()
            XCTAssertTrue(reopened.hasShownGuide)
            XCTAssertFalse(reopened.hasCompletedGuide)
            reopened.begin()
            XCTAssertEqual(reopened.step, .camera)
        }
    }

    func testCancelledPreparationBeforePresentationDoesNotMarkGuideAsShown() {
        withRepository { repository, _ in
            repository.begin()
            repository.dismiss()
            XCTAssertFalse(repository.hasShownGuide)
            XCTAssertFalse(OnboardingRepository().hasShownGuide)
        }
    }

    func testPreviouslyCompletedGuideCountsAsAlreadyShown() {
        withRepository { repository, defaults in
            defaults.set(true, forKey: "facenow.onboarding.completed.v1")
            XCTAssertTrue(repository.hasShownGuide)
            XCTAssertTrue(OnboardingRepository().hasShownGuide)
            XCTAssertFalse(defaults.bool(forKey: "facenow.onboarding.shown.v1"))
        }
    }

    func testReviewBeginsAtCameraAndVisitsEveryReadyPage() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true)
            repository.begin(at: .virtualCamera, fromFirstStep: true)
            for expected: OnboardingRepository.Step in [.camera, .virtualCamera, .microphone, .virtualMicrophone, .videoCalls] {
                XCTAssertEqual(repository.step, expected)
                if expected != .videoCalls { repository.advance() }
            }
            repository.dismiss()
            repository.begin(fromFirstStep: true)
            XCTAssertEqual(repository.step, .camera)
        }
    }

    func testReadinessRefreshCannotSkipReviewAndNormalEntryCanBeRestored() {
        withRepository { repository, _ in
            repository.begin(fromFirstStep: true)
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true)
            XCTAssertEqual(repository.step, .camera)
            repository.advance()
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: false)
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true)
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.dismiss()
            repository.begin()
            XCTAssertEqual(repository.step, .videoCalls)
        }
    }

    func testNewCameraAuthorizationAdvancesReviewToVirtualCameraWithoutSkippingIt() {
        withRepository { repository, _ in
            repository.begin(fromFirstStep: true)
            repository.advance()
            repository.advance()
            XCTAssertEqual(repository.step, .camera)
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true, cameraAccessJustGranted: true)
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true)
            XCTAssertEqual(repository.step, .virtualCamera)
        }
    }

    func testNewPermissionAdvancesWhileInputDiscoveryIsStillPending() {
        withRepository { repository, _ in
            repository.begin(fromFirstStep: true)
            repository.advance()
            repository.advance()
            repository.updateReadiness(camera: false, microphone: true, virtualMicrophone: true, virtualCamera: false, cameraAccessJustGranted: true)
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: false)
            XCTAssertEqual(repository.step, .virtualCamera)
        }
    }

    func testPermissionGrantedAfterDismissalDoesNotChangeTheStage() {
        withRepository { repository, _ in
            repository.begin(fromFirstStep: true)
            repository.dismiss()
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true, cameraAccessJustGranted: true)
            XCTAssertEqual(repository.step, .camera)
            XCTAssertFalse(repository.isPresented)
        }
    }

    func testMissingMicrophonePreventsAdvancingToPreparedVideoSteps() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, microphone: false, virtualMicrophone: true, virtualCamera: true)
            repository.begin()
            XCTAssertEqual(repository.step, .microphone)
            repository.advance()
            XCTAssertEqual(repository.step, .microphone)
            repository.complete()
            XCTAssertFalse(repository.hasCompletedGuide)
        }
    }

    func testCameraPreparationPrecedesMicrophonePermission() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, microphone: false, virtualMicrophone: true, virtualCamera: false)
            repository.begin()
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.updateReadiness(camera: true, microphone: false, virtualMicrophone: true, virtualCamera: true)
            XCTAssertEqual(repository.step, .microphone)
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true, microphoneAccessJustGranted: true)
            XCTAssertEqual(repository.step, .videoCalls)
        }
    }

    func testMicrophoneSkipPersistsWithoutClaimingPermissionAndAllowsCompletion() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, microphone: false, virtualMicrophone: true, virtualCamera: true)
            repository.begin()
            repository.skipAudio()
            XCTAssertEqual(repository.step, .videoCalls)
            XCTAssertFalse(repository.microphoneReady)
            XCTAssertTrue(repository.microphoneSkipped)
            repository.complete()
            XCTAssertTrue(repository.hasCompletedGuide)

            let reopened = OnboardingRepository()
            reopened.updateReadiness(camera: true, microphone: false, virtualMicrophone: true, virtualCamera: true)
            reopened.begin()
            XCTAssertTrue(reopened.microphoneSkipped)
            XCTAssertEqual(reopened.step, .videoCalls)
        }
    }

    func testAudioSkipRetainsVirtualCameraRequirementAndCanBeRevisited() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, microphone: false, virtualMicrophone: false, virtualCamera: false)
            repository.begin(at: .microphone)
            repository.skipAudio()
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.complete()
            XCTAssertFalse(repository.hasCompletedGuide)
            repository.previous()
            XCTAssertEqual(repository.step, .camera)
            repository.begin(at: .microphone)
            XCTAssertEqual(repository.step, .microphone)
            repository.advance()
            XCTAssertEqual(repository.step, .virtualCamera)
        }
    }

    func testMicrophoneSkipCannotBypassCameraOrChangeADismissedGuide() {
        withRepository { repository, _ in
            repository.begin()
            repository.skipAudio()
            XCTAssertEqual(repository.step, .camera)
            XCTAssertFalse(repository.microphoneSkipped)
            repository.updateReadiness(camera: true, microphone: false, virtualMicrophone: true, virtualCamera: true)
            repository.dismiss()
            repository.skipAudio()
            XCTAssertEqual(repository.step, .microphone)
            XCTAssertFalse(repository.microphoneSkipped)
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true, microphoneAccessJustGranted: true)
            XCTAssertEqual(repository.step, .microphone)
        }
    }

    func testMicrophoneGrantClearsDeferralAndRevocationReturnsToPermissionStep() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, microphone: false, virtualMicrophone: true, virtualCamera: true)
            repository.begin()
            repository.skipAudio()
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true)
            XCTAssertFalse(repository.microphoneSkipped)
            repository.updateReadiness(camera: true, microphone: false, virtualMicrophone: true, virtualCamera: true)
            XCTAssertEqual(repository.step, .microphone)
        }
    }

    func testFreshGuidePreparesVideoBeforeOneOptionalAudioDecision() {
        withRepository { _, _ in
            let repository = OnboardingRepository()
            repository.begin()
            XCTAssertEqual(repository.step, .camera)
            repository.skipAudio()
            XCTAssertFalse(repository.microphoneSkipped)
            repository.updateReadiness(camera: true, microphone: false, virtualMicrophone: false, virtualCamera: false)
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.updateReadiness(camera: true, microphone: false, virtualMicrophone: false, virtualCamera: true)
            XCTAssertEqual(repository.step, .microphone)
            repository.skipAudio()
            XCTAssertEqual(repository.step, .videoCalls)
            XCTAssertTrue(repository.microphoneSkipped)
            XCTAssertTrue(repository.virtualMicrophoneSkipped)
            XCTAssertFalse(repository.microphoneReady)
            XCTAssertFalse(repository.virtualMicrophoneReady)
            XCTAssertFalse(repository.hasCompletedGuide)
            repository.complete()
            XCTAssertTrue(repository.hasCompletedGuide)
        }
    }

    func testSkippingAudioDoesNotOfferAnotherAudioPageAndPersistsBothDecisions() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, microphone: false, virtualMicrophone: false, virtualCamera: true)
            repository.begin()
            repository.skipAudio()
            XCTAssertEqual(repository.step, .videoCalls)
            XCTAssertTrue(repository.microphoneSkipped)
            XCTAssertTrue(repository.virtualMicrophoneSkipped)
            let reopened = OnboardingRepository()
            reopened.updateReadiness(camera: true, microphone: false, virtualMicrophone: false, virtualCamera: true)
            reopened.begin()
            XCTAssertEqual(reopened.step, .videoCalls)
        }
    }

    func testSkippingVirtualMicrophonePreservesPhysicalPermissionAndCameraRequirement() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: false, microphone: true, virtualMicrophone: false, virtualCamera: true)
            repository.begin(at: .virtualMicrophone)
            repository.skipAudio()
            XCTAssertEqual(repository.step, .camera)
            XCTAssertTrue(repository.microphoneReady)
            XCTAssertFalse(repository.microphoneSkipped)
            repository.complete()
            XCTAssertFalse(repository.hasCompletedGuide)
        }
    }

    func testVirtualMicrophoneSkipPersistsAndAllowsCompletionWithoutFakingReadiness() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: false, virtualCamera: true)
            repository.begin()
            repository.skipAudio()
            XCTAssertFalse(repository.virtualMicrophoneReady)
            XCTAssertTrue(repository.virtualMicrophoneSkipped)
            repository.complete()
            XCTAssertTrue(repository.hasCompletedGuide)
            let reopened = OnboardingRepository()
            reopened.updateReadiness(camera: true, microphone: true, virtualMicrophone: false, virtualCamera: true)
            reopened.begin()
            XCTAssertEqual(reopened.step, .videoCalls)
            reopened.previous()
            XCTAssertEqual(reopened.step, .virtualMicrophone)
        }
    }

    func testVirtualMicrophoneActivationClearsDeferralAndLaterFailureReturnsToSetup() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: false, virtualCamera: true)
            repository.begin()
            repository.skipAudio()
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: true, virtualCamera: true)
            XCTAssertFalse(repository.virtualMicrophoneSkipped)
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: false, virtualCamera: true)
            XCTAssertEqual(repository.step, .virtualMicrophone)
        }
    }

    func testDismissedVirtualMicrophoneStepRejectsLateSkipAndKeepsRelaunchRequirements() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: false, virtualCamera: true)
            repository.begin()
            repository.dismiss()
            repository.skipAudio()
            XCTAssertFalse(repository.virtualMicrophoneSkipped)
            OnboardingRepository(processID: 101).prepareForRelaunch()
            let replacement = OnboardingRepository(processID: 202)
            replacement.updateReadiness(camera: true, microphone: true, virtualMicrophone: false, virtualCamera: true)
            replacement.begin(at: replacement.resumeStepAfterRelaunch)
            XCTAssertEqual(replacement.step, .virtualMicrophone)
            XCTAssertFalse(replacement.hasCompletedGuide)
        }
    }

    func testProgressGroupsBothAudioPagesIntoOneOptionalStage() {
        XCTAssertEqual(OnboardingRepository.Stage.allCases, [.camera, .virtualCamera, .audio, .videoCalls])
        XCTAssertEqual(OnboardingRepository.Step.microphone.stage, .audio)
        XCTAssertEqual(OnboardingRepository.Step.virtualMicrophone.stage, .audio)
    }

    func testRelaunchAfterCameraRegistrationResumesUnfinishedAudioSetup() {
        withRepository { _, _ in
            OnboardingRepository(processID: 101).prepareForRelaunch()
            let replacement = OnboardingRepository(processID: 202)
            replacement.updateReadiness(camera: true, microphone: false, virtualMicrophone: false, virtualCamera: true)
            replacement.begin(at: replacement.resumeStepAfterRelaunch)
            XCTAssertEqual(replacement.step, .microphone)
            replacement.recordPresentation()
            XCTAssertNil(replacement.resumeStepAfterRelaunch)
            replacement.skipAudio()
            XCTAssertEqual(replacement.step, .videoCalls)
            XCTAssertFalse(replacement.hasCompletedGuide)
        }
    }

    func testDeferredAudioDoesNotReappearWhenPhysicalPermissionChanges() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, microphone: true, virtualMicrophone: false, virtualCamera: true)
            repository.begin()
            repository.skipAudio()
            XCTAssertEqual(repository.step, .videoCalls)
            repository.updateReadiness(camera: true, microphone: false, virtualMicrophone: false, virtualCamera: true)
            XCTAssertEqual(repository.step, .videoCalls)
            XCTAssertFalse(repository.microphoneReady)
            XCTAssertTrue(repository.virtualMicrophoneSkipped)
        }
    }

    private func withRepository(
        _ body: (OnboardingRepository, UserDefaults) -> Void
    ) {
        let suite = "FaceNow.OnboardingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = Container()
        Container.$shared.withValue(container) {
            Scope.$singleton.withValue(Scope.Singleton()) {
                container.userDefaults.register { @MainActor in defaults }
                let repository = OnboardingRepository()
                repository.updateReadiness(camera: false, microphone: true, virtualMicrophone: true, virtualCamera: false)
                body(repository, defaults)
            }
        }
    }
}
