import Factory
import Foundation
import XCTest
@testable import FNOnboarding

@MainActor
final class OnboardingRepositoryTests: XCTestCase {

    func testPreparationResumesAtTheFirstMissingDeviceStep() {
        withRepository { repository, _ in
            repository.begin()
            XCTAssertEqual(repository.step, .camera)
            repository.updateReadiness(camera: true, virtualCamera: false)
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.dismiss()
            XCTAssertFalse(repository.hasCompletedGuide)
            repository.begin()
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.updateReadiness(camera: true, virtualCamera: true)
            XCTAssertEqual(repository.step, .videoCalls)
            repository.dismiss()
            repository.begin()
            XCTAssertEqual(repository.step, .videoCalls)
            XCTAssertFalse(repository.hasCompletedGuide)
        }
    }

    func testCompletedDeviceSettingsAreSkippedOnEntry() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, virtualCamera: true)
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
            repository.updateReadiness(camera: true, virtualCamera: false)
            repository.complete()
            XCTAssertFalse(repository.hasCompletedGuide)
            repository.updateReadiness(camera: true, virtualCamera: true)
            repository.complete()
            XCTAssertTrue(repository.hasCompletedGuide)
            XCTAssertFalse(repository.isPresented)
            let reopened = OnboardingRepository()
            XCTAssertTrue(reopened.hasCompletedGuide)
            reopened.updateReadiness(camera: false, virtualCamera: true)
            reopened.begin()
            XCTAssertEqual(reopened.step, .camera)
        }
    }

    func testPermissionOrOutputLossReturnsToTheMissingRequirement() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, virtualCamera: true)
            repository.begin()
            repository.updateReadiness(camera: true, virtualCamera: false)
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.updateReadiness(camera: false, virtualCamera: false)
            XCTAssertEqual(repository.step, .camera)
            repository.advance()
            XCTAssertEqual(repository.step, .camera)
            repository.updateReadiness(camera: true, virtualCamera: false)
            XCTAssertEqual(repository.step, .virtualCamera)
        }
    }

    func testRevisitedReadyStepDoesNotAdvanceUntilTheUserContinues() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, virtualCamera: true)
            repository.begin()
            repository.previous()
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.updateReadiness(camera: true, virtualCamera: true)
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.previous()
            XCTAssertEqual(repository.step, .camera)
            repository.advance()
            XCTAssertEqual(repository.step, .videoCalls)
        }
    }

    func testRequestedRepairStepAndDeferralDoNotOverwriteCompletion() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, virtualCamera: true)
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
            repository.updateReadiness(camera: true, virtualCamera: true)
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

    func testReviewBeginsAtCameraAndVisitsEveryReadyStep() {
        withRepository { repository, _ in
            repository.updateReadiness(camera: true, virtualCamera: true)
            repository.begin(at: .virtualCamera, fromFirstStep: true)
            XCTAssertEqual(repository.step, .camera)
            repository.advance()
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.advance()
            XCTAssertEqual(repository.step, .videoCalls)
            repository.dismiss()
            repository.begin(fromFirstStep: true)
            XCTAssertEqual(repository.step, .camera)
        }
    }

    func testReadinessRefreshCannotSkipReviewAndNormalEntryCanBeRestored() {
        withRepository { repository, _ in
            repository.begin(fromFirstStep: true)
            repository.updateReadiness(camera: true, virtualCamera: true)
            XCTAssertEqual(repository.step, .camera)
            repository.advance()
            repository.updateReadiness(camera: true, virtualCamera: false)
            repository.updateReadiness(camera: true, virtualCamera: true)
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.dismiss()
            repository.begin()
            XCTAssertEqual(repository.step, .videoCalls)
        }
    }

    func testNewCameraAuthorizationAdvancesReviewToVirtualCameraWithoutSkippingIt() {
        withRepository { repository, _ in
            repository.begin(fromFirstStep: true)
            repository.updateReadiness(camera: true, virtualCamera: true, cameraAccessJustGranted: true)
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.updateReadiness(camera: true, virtualCamera: true)
            XCTAssertEqual(repository.step, .virtualCamera)
        }
    }

    func testNewPermissionAdvancesWhileInputDiscoveryIsStillPending() {
        withRepository { repository, _ in
            repository.begin(fromFirstStep: true)
            repository.updateReadiness(camera: false, virtualCamera: false, cameraAccessJustGranted: true)
            XCTAssertEqual(repository.step, .virtualCamera)
            repository.updateReadiness(camera: true, virtualCamera: false)
            XCTAssertEqual(repository.step, .virtualCamera)
        }
    }

    func testPermissionGrantedAfterDismissalDoesNotChangeTheStage() {
        withRepository { repository, _ in
            repository.begin(fromFirstStep: true)
            repository.dismiss()
            repository.updateReadiness(camera: true, virtualCamera: true, cameraAccessJustGranted: true)
            XCTAssertEqual(repository.step, .camera)
            XCTAssertFalse(repository.isPresented)
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
                body(OnboardingRepository(), defaults)
            }
        }
    }
}
