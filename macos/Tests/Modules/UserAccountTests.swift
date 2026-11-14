import Combine
import Foundation
import Moya
import XCTest
import FNNetwork
import Storage
@testable import FNUser

@MainActor
final class UserAccountTests: XCTestCase {

    func testRechargeNoticesCoalesceAndIgnoreOldDialogCompletions() async throws {
        let context = makeContext(routes: [
            "/baas/api/user/apikey/list": activeAPIKeyResponse,
            "/baas/api/user/info": apiKeyProfileResponse,
        ])
        defer { context.cleanup() }
        try await context.account.signIn(apiKey: activeAPIKey)
        XCTAssertNil(context.account.remainingCredits)
        context.account.requestRechargeNotice()
        let first = try XCTUnwrap(context.account.rechargeNoticeID)
        context.account.requestRechargeNotice()
        XCTAssertEqual(context.account.rechargeNoticeID, first)
        context.account.dismissRechargeNotice(id: first)
        XCTAssertNil(context.account.rechargeNoticeID)
        context.account.requestRechargeNotice()
        let second = try XCTUnwrap(context.account.rechargeNoticeID)
        XCTAssertNotEqual(first, second)
        context.account.dismissRechargeNotice(id: first)
        XCTAssertEqual(context.account.rechargeNoticeID, second)
    }

    func testRuntimeRechargeNoticePreservesBalanceAndIsClearedOnSignOut() async throws {
        let context = makeContext(routes: [
            "/baas/api/user/apikey/list": activeAPIKeyResponse,
            "/baas/api/user/info": apiKeyProfileResponse,
            "/open/api/v1/points/balance": #"{"success":true,"code":200,"data":{"currentBalance":1250}}"#,
        ])
        defer { context.cleanup() }
        context.account.requestRechargeNotice()
        XCTAssertNil(context.account.rechargeNoticeID)
        try await context.account.signIn(apiKey: activeAPIKey)
        await context.account.refreshCredits()
        context.account.requestRechargeNotice()
        XCTAssertNotNil(context.account.rechargeNoticeID)
        XCTAssertEqual(context.account.remainingCredits, 1250)
        XCTAssertEqual(context.account.apiKey, activeAPIKey)
        try await context.account.signOut()
        XCTAssertNil(context.account.rechargeNoticeID)
        context.account.requestRechargeNotice()
        XCTAssertNil(context.account.rechargeNoticeID)
    }

    func testVerifiedAPIKeyCanLoadCreditsWithoutChangingGenerationCredential() async throws {
        let context = makeContext(routes: [
            "/baas/api/user/apikey/list": activeAPIKeyResponse,
            "/baas/api/user/info": apiKeyProfileResponse,
            "/open/api/v1/points/balance": #"{"success":true,"code":200,"data":{"currentBalance":1250.75}}"#,
        ])
        defer { context.cleanup() }
        try await context.account.signIn(apiKey: activeAPIKey)
        XCTAssertNil(context.account.remainingCredits)
        XCTAssertFalse(context.account.hasInsufficientCredits)
        await context.account.refreshCredits()
        XCTAssertEqual(context.account.remainingCredits, 1250.75)
        XCTAssertFalse(context.account.hasInsufficientCredits)
        XCTAssertEqual(context.account.apiKey, activeAPIKey)
        XCTAssertNil(context.account.creditsErrorMessage)
        XCTAssertFalse(context.account.isLoadingCredits)
        try await context.account.signOut()
        XCTAssertNil(context.account.remainingCredits)
    }

    func testForcedCreditsRefreshBypassesThePollingInterval() async throws {
        let context = makeContext(routes: [
            "/baas/api/user/apikey/list": activeAPIKeyResponse,
            "/baas/api/user/info": apiKeyProfileResponse,
            "/open/api/v1/points/balance": #"{"success":true,"code":200,"data":{"currentBalance":1250}}"#,
        ])
        defer { context.cleanup() }
        try await context.account.signIn(apiKey: activeAPIKey)
        var updates = 0
        let observation = context.account.$remainingCredits.compactMap { $0 }.sink { _ in updates += 1 }
        defer { observation.cancel() }
        await context.account.refreshCredits()
        await context.account.refreshCredits()
        XCTAssertEqual(updates, 1, "Ordinary polling remains throttled")
        await context.account.refreshCredits(force: true)
        XCTAssertEqual(updates, 2, "Closing a session must fetch credits immediately")
    }

    func testForcedCreditsRefreshSupersedesAnInFlightPoll() async throws {
        let context = makeContext(routes: [
            "/baas/api/user/apikey/list": activeAPIKeyResponse,
            "/baas/api/user/info": apiKeyProfileResponse,
            "/open/api/v1/points/balance": #"{"success":true,"code":200,"data":{"currentBalance":1250}}"#,
        ], delay: 0.2)
        defer { context.cleanup() }
        try await context.account.signIn(apiKey: activeAPIKey)
        let started = expectation(description: "Background poll started")
        var starts = 0
        var updates = 0
        let loading = context.account.$isLoadingCredits.dropFirst().sink { value in
            if value {
                starts += 1
                if starts == 1 { started.fulfill() }
            }
        }
        let credits = context.account.$remainingCredits.compactMap { $0 }.sink { _ in updates += 1 }
        defer { loading.cancel(); credits.cancel() }
        let poll = _Concurrency.Task { await context.account.refreshCredits() }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(context.account.isLoadingCredits)
        await context.account.refreshCredits(force: true)
        await poll.value
        XCTAssertEqual(starts, 2, "The close refresh must not be swallowed by a pending poll")
        XCTAssertEqual(updates, 1, "A superseded balance must not update the header")
        XCTAssertEqual(context.account.remainingCredits, 1250)
        XCTAssertFalse(context.account.isLoadingCredits)
    }

    func testUnavailableBalanceDoesNotBecomeZeroOrInvalidateAnOtherwiseValidAccount() async throws {
        let context = makeContext(routes: [
            "/baas/api/user/apikey/list": activeAPIKeyResponse,
            "/baas/api/user/info": apiKeyProfileResponse,
            "/open/api/v1/points/balance": #"{"success":false,"code":503,"message":"Try later","data":null}"#,
        ])
        defer { context.cleanup() }
        try await context.account.signIn(apiKey: activeAPIKey)
        await context.account.refreshCredits()
        XCTAssertNil(context.account.remainingCredits)
        XCTAssertEqual(context.account.creditsErrorMessage, "Try later")
        XCTAssertFalse(context.account.hasInsufficientCredits)
        XCTAssertTrue(context.account.canAccessHome)
        let model = UserAccountViewModel(user: context.account)
        XCTAssertEqual(model.creditsText, "—")
        XCTAssertTrue(model.creditsHelp.contains("unavailable"))
    }

    func testLateBalanceCannotRepopulateASignedOutAccount() async throws {
        let context = makeContext(
            routes: [
                "/baas/api/user/apikey/list": activeAPIKeyResponse,
                "/baas/api/user/info": apiKeyProfileResponse,
                "/open/api/v1/points/balance": #"{"success":true,"code":200,"data":{"currentBalance":999}}"#,
            ],
            delay: 0.08
        )
        defer { context.cleanup() }
        try await context.account.signIn(apiKey: activeAPIKey)
        let refresh = _Concurrency.Task { await context.account.refreshCredits() }
        try await _Concurrency.Task.sleep(for: .milliseconds(10))
        try await context.account.signOut()
        await refresh.value
        XCTAssertNil(context.account.remainingCredits)
        XCTAssertNil(context.account.creditsErrorMessage)
        XCTAssertFalse(context.account.isLoadingCredits)
        XCTAssertFalse(context.account.canAccessHome)
    }

    func testProfileProvidesTextAvatarAndConfirmedZeroIsDisplayed() async throws {
        let context = makeContext(routes: [
            "/baas/api/user/info": #"{"success":true,"code":200,"data":{"uid":"user","phone":"13800000042"}}"#,
            "/baas/api/user/apikey/list": keysResponse,
            "/open/api/v1/points/balance": #"{"success":true,"code":200,"data":{"currentBalance":0}}"#,
        ])
        defer { context.cleanup() }
        context.store.value = "test-session"
        await context.account.restore()
        await context.account.refreshCredits()
        let model = UserAccountViewModel(user: context.account)
        XCTAssertEqual(model.avatarText, "13")
        XCTAssertEqual(model.creditsText, "0")
        XCTAssertTrue(context.account.hasInsufficientCredits)
    }

    func testSavedSDKKeyAloneNeverGrantsHomeAccess() async {
        let context = makeContext(routes: [:])
        defer { context.cleanup() }
        context.account.apiKey = activeAPIKey
        XCTAssertTrue(context.account.hasAPIKey)
        XCTAssertFalse(context.account.canAccessHome)
        await context.account.restore()
        XCTAssertFalse(context.account.isSignedIn)
        XCTAssertFalse(context.account.canAccessHome)
        XCTAssertNil(context.store.value)
    }

    func testSelectingAPIKeyInputDoesNotAuthenticateTheUser() async {
        let context = makeContext(routes: [:])
        defer { context.cleanup() }
        let form = UserLoginViewModel()
        form.selectAPIKey(true)
        XCTAssertTrue(form.usesAPIKey)
        XCTAssertFalse(context.account.canAccessHome)
        XCTAssertNil(context.account.profile)
        XCTAssertNil(context.store.value)
    }

    func testAPIKeySignInRequiresAnActiveRecordAndPublishesItsFetchedProfile() async throws {
        let context = makeContext(routes: [
            "/baas/api/user/apikey/list": activeAPIKeyResponse,
            "/baas/api/user/info": apiKeyProfileResponse,
        ])
        defer { context.cleanup() }
        var signInCount = 0
        let observation = context.account.signInCompleted.sink {
            signInCount += 1
            XCTAssertEqual(context.account.profile?.nickname, "Test account")
            XCTAssertEqual(context.store.value, self.activeAPIKey)
            XCTAssertTrue(context.account.canAccessHome)
        }
        defer { observation.cancel() }
        try await context.account.signIn(apiKey: "  \(activeAPIKey)\n")
        XCTAssertEqual(signInCount, 1)
        XCTAssertEqual(context.account.profile?.email, "test@example.invalid")
        XCTAssertEqual(context.account.displayName, "Test account")
        XCTAssertTrue(context.account.canAccessHome)
        XCTAssertEqual(
            context.account.profile?.uid,
            "api-key-user"
        )
        XCTAssertEqual(
            context.account.apiKey,
            activeAPIKey
        )
        XCTAssertEqual(
            context.store.value,
            activeAPIKey
        )
        XCTAssertEqual(
            context.account.keys.count,
            1
        )
    }

    func testAPIKeyProfileFailureCannotCommitSessionOrEmitSuccess() async {
        let responses = [
            #"{"success":false,"code":503,"message":"Try later","data":null}"#,
            #"{"success":false,"code":401,"message":"Unauthorized","data":null}"#,
            #"{"success":true,"code":200,"data":null}"#,
            #"{"success":true,"code":200,"data":{"nickname":"Missing identity"}}"#,
            #"{"success":true,"code":200,"data":{"uid":"another-user"}}"#,
        ]
        for response in responses {
            let context = makeContext(routes: [
                "/baas/api/user/apikey/list": activeAPIKeyResponse,
                "/baas/api/user/info": response,
            ])
            defer { context.cleanup() }
            var signInCount = 0
            let observation = context.account.signInCompleted.sink { signInCount += 1 }
            defer { observation.cancel() }
            do {
                try await context.account.signIn(apiKey: activeAPIKey)
                XCTFail("Expected profile validation to fail")
            } catch {}
            XCTAssertFalse(context.account.canAccessHome)
            XCTAssertFalse(context.account.isBusy)
            XCTAssertNil(context.account.profile)
            XCTAssertNil(context.store.value)
            XCTAssertTrue(context.account.keys.isEmpty)
            XCTAssertEqual(context.account.apiKey, "")
            XCTAssertEqual(signInCount, 0)
        }
    }

    func testAPIKeyProfileFailureDuringRestorationKeepsHomeClosed() async {
        for unauthorized in [false, true] {
            let response =
                unauthorized
                ? #"{"success":false,"code":401,"message":"Unauthorized","data":null}"#
                : #"{"success":false,"code":503,"message":"Try later","data":null}"#
            let context = makeContext(routes: [
                "/baas/api/user/apikey/list": activeAPIKeyResponse,
                "/baas/api/user/info": response,
            ])
            defer { context.cleanup() }
            context.store.value = activeAPIKey
            await context.account.restore()
            XCTAssertFalse(context.account.canAccessHome)
            XCTAssertFalse(context.account.isRestoring)
            XCTAssertNil(context.account.profile)
            XCTAssertEqual(context.store.value, unauthorized ? nil : activeAPIKey)
            XCTAssertNotNil(context.account.errorMessage)
        }
    }

    func testRejectedAPIKeyCannotPersistCredentialsOrGrantHomeAccess() async {
        let context = makeContext(routes: [
            "/baas/api/user/apikey/list": #"{"success":false,"code":401,"message":"Invalid key","data":null}"#
        ])
        defer { context.cleanup() }
        do {
            try await context.account.signIn(apiKey: "uk-invalid")
            XCTFail("Expected key rejection")
        } catch let error as NetworkError { XCTAssertTrue(error.isUnauthorized) } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertFalse(context.account.canAccessHome)
        XCTAssertNil(context.account.profile)
        XCTAssertNil(context.store.value)
        XCTAssertEqual(
            context.account.apiKey,
            ""
        )
    }

    func testUnmatchedAPIKeyCannotUseAnOtherwiseSuccessfulListResponseToSignIn() async {
        let context = makeContext(routes: ["/baas/api/user/apikey/list": keysResponse])
        defer { context.cleanup() }
        do {
            try await context.account.signIn(apiKey: activeAPIKey)
            XCTFail("Expected the exact active key record")
        } catch let error as NetworkError { XCTAssertTrue(error.isUnauthorized) } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertFalse(context.account.canAccessHome)
        XCTAssertNil(context.store.value)
    }

    func testEmptyAPIKeyFailsBeforeItCanAuthenticate() async {
        let context = makeContext(routes: [:])
        defer { context.cleanup() }
        do {
            try await context.account.signIn(apiKey: " \n")
            XCTFail("Expected input validation")
        } catch let error as NetworkError {
            guard
                case .server(
                    let code,
                    _
                ) = error
            else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(
                code,
                400
            )
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(context.account.canAccessHome)
        XCTAssertNil(context.store.value)
    }

    func testSavedAPIKeyOpensHomeWhileGenerationWaitsForVerification() async throws {
        let context = makeContext(
            routes: [
                "/baas/api/user/apikey/list": activeAPIKeyResponse,
                "/baas/api/user/info": apiKeyProfileResponse,
            ],
            delay: 0.05
        )
        defer { context.cleanup() }
        context.store.value = activeAPIKey
        let restoration = _Concurrency.Task { await context.account.restore() }
        try await _Concurrency.Task.sleep(for: .milliseconds(10))
        XCTAssertTrue(context.account.isRestoring)
        XCTAssertTrue(context.account.canAccessHome)
        XCTAssertFalse(context.account.hasVerifiedSession)
        await restoration.value
        XCTAssertTrue(context.account.canAccessHome)
        XCTAssertTrue(context.account.hasVerifiedSession)
        XCTAssertEqual(
            context.account.profile?.uid,
            "api-key-user"
        )
    }

    func testRevokedAPIKeyRestorationClearsTheSessionAndKeepsLoginRequired() async {
        let context = makeContext(routes: [
            "/baas/api/user/apikey/list": #"{"success":true,"code":200,"data":[]}"#
        ])
        defer { context.cleanup() }
        context.store.value = activeAPIKey
        context.account.apiKey = activeAPIKey
        await context.account.restore()
        XCTAssertFalse(context.account.canAccessHome)
        XCTAssertNil(context.store.value)
        XCTAssertEqual(
            context.account.apiKey,
            ""
        )
    }

    func testLateAPIKeyVerificationCannotRecreateASignedOutSession() async throws {
        let context = makeContext(
            routes: [
                "/baas/api/user/apikey/list": activeAPIKeyResponse,
                "/baas/api/user/info": apiKeyProfileResponse,
            ],
            delay: 0.08
        )
        defer { context.cleanup() }
        let login = _Concurrency.Task { try await context.account.signIn(apiKey: activeAPIKey) }
        try await _Concurrency.Task.sleep(for: .milliseconds(10))
        try await context.account.signOut()
        do {
            try await login.value
            XCTFail("Expected the old operation to be rejected")
        } catch is CancellationError {
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(context.account.canAccessHome)
        XCTAssertNil(context.store.value)
        XCTAssertNil(context.account.profile)
    }

    func testCachedProfileOpensHomeBeforeAnyRequestAndRefreshesInBackground() async throws {
        let context = makeContext(routes: [
            "/baas/api/user/login": #"{"success":true,"code":200,"data":"test-session"}"#,
            "/baas/api/user/info": #"{"success":true,"code":200,"data":{"uid":"user","nickname":"Cached name"}}"#,
            "/baas/api/user/apikey/list": keysResponse,
        ])
        defer { context.cleanup() }
        try await context.account.signIn(
            method: .sms,
            account: "13800000000",
            code: "123456",
            proof: CaptchaProof()
        )
        let refreshed = makeContext(routes: [
            "/baas/api/user/info": #"{"success":true,"code":200,"data":{"uid":"user","nickname":"Updated name"}}"#,
            "/baas/api/user/apikey/list": keysResponse,
        ])
        defer { refreshed.cleanup() }
        let relaunched = UserRepository(defaults: context.defaults, client: refreshed.client, store: context.store)
        XCTAssertTrue(relaunched.canAccessHome)
        XCTAssertFalse(relaunched.hasVerifiedSession)
        XCTAssertEqual(relaunched.profile?.nickname, "Cached name")
        let data = try XCTUnwrap(context.defaults.data(forKey: "xmax.camera.accountProfile"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("test-session"))
        await relaunched.restore()
        XCTAssertTrue(relaunched.hasVerifiedSession)
        XCTAssertEqual(relaunched.profile?.nickname, "Updated name")
        let nextLaunch = UserRepository(defaults: context.defaults, client: refreshed.client, store: context.store)
        XCTAssertEqual(nextLaunch.profile?.nickname, "Updated name")
    }

    func testCachedHomeReturnsToLoginWithNoticeOnBackgroundFailure() async throws {
        for code in [401, 503] {
            let context = makeContext(routes: [
                "/baas/api/user/apikey/list": activeAPIKeyResponse,
                "/baas/api/user/info": apiKeyProfileResponse,
            ])
            defer { context.cleanup() }
            try await context.account.signIn(apiKey: activeAPIKey)
            let failure = makeContext(routes: [
                "/baas/api/user/apikey/list": activeAPIKeyResponse,
                "/baas/api/user/info": "{\"success\":false,\"code\":\(code),\"message\":\"Failed\",\"data\":null}",
            ])
            defer { failure.cleanup() }
            let relaunched = UserRepository(defaults: context.defaults, client: failure.client, store: context.store)
            XCTAssertTrue(relaunched.canAccessHome)
            XCTAssertEqual(relaunched.profile?.uid, "api-key-user")
            await relaunched.restore()
            XCTAssertFalse(relaunched.canAccessHome)
            XCTAssertFalse(relaunched.hasVerifiedSession)
            XCTAssertNil(relaunched.profile)
            XCTAssertNil(context.defaults.data(forKey: "xmax.camera.accountProfile"))
            XCTAssertEqual(context.store.value, code == 401 ? nil : activeAPIKey)
            XCTAssertEqual(
                relaunched.sessionNotice,
                code == 401
                    ? "Your session has expired. Please sign in again."
                    : "Unable to verify your session. Check your connection and sign in again."
            )
            relaunched.dismissSessionNotice()
            XCTAssertNil(relaunched.sessionNotice)
        }
    }

    func testProfileCacheNeverDisplaysForAnotherCredential() async throws {
        let context = makeContext(routes: [
            "/baas/api/user/apikey/list": activeAPIKeyResponse,
            "/baas/api/user/info": apiKeyProfileResponse,
        ])
        defer { context.cleanup() }
        try await context.account.signIn(apiKey: activeAPIKey)
        context.store.value = "another-session"
        let relaunched = UserRepository(defaults: context.defaults, client: context.client, store: context.store)
        XCTAssertNil(relaunched.profile)
        XCTAssertNil(context.defaults.data(forKey: "xmax.camera.accountProfile"))
        XCTAssertFalse(relaunched.hasVerifiedSession)
    }

    func testLateCachedSessionRefreshCannotUndoLogoutOrRecreateProfileCache() async throws {
        let context = makeContext(
            routes: [
                "/baas/api/user/apikey/list": activeAPIKeyResponse,
                "/baas/api/user/info": apiKeyProfileResponse,
            ],
            delay: 0.05
        )
        defer { context.cleanup() }
        try await context.account.signIn(apiKey: activeAPIKey)
        let relaunched = UserRepository(defaults: context.defaults, client: context.client, store: context.store)
        XCTAssertTrue(relaunched.canAccessHome)
        let restoration = _Concurrency.Task { await relaunched.restore() }
        try await _Concurrency.Task.sleep(for: .milliseconds(10))
        try await relaunched.signOut()
        await restoration.value
        XCTAssertFalse(relaunched.canAccessHome)
        XCTAssertNil(relaunched.profile)
        XCTAssertNil(context.store.value)
        XCTAssertNil(context.defaults.data(forKey: "xmax.camera.accountProfile"))
        let nextLaunch = UserRepository(defaults: context.defaults, client: context.client, store: context.store)
        XCTAssertFalse(nextLaunch.canAccessHome)
    }

    private var activeAPIKey: String {
        "uk-"
            + String(
                repeating: "a",
                count: 20
            )
    }

    private var apiKeyProfileResponse: String {
        #"{"success":true,"code":200,"data":{"uid":"api-key-user","nickname":"Test account","email":"test@example.invalid"}}"#
    }

    private var activeAPIKeyResponse: String {
        """
        {"success":true,"code":200,"data":[{"uid":"api-key-record","tenantName":"open-platform","userUid":"api-key-user","name":"FaceNow","apiKey":"\(activeAPIKey)","status":"active"}]}
        """
    }

    func testFailedKeyLookupCannotExposeAnUnvalidatedSDKKeyAfterRestoration() async {
        let context = makeContext(routes: [
            "/baas/api/user/info": #"{"success":true,"code":200,"data":{"uid":"user"}}"#,
            "/baas/api/user/apikey/list": #"{"success":false,"code":503,"message":"Try later","data":null}"#,
        ])
        defer { context.cleanup() }
        context.store.value = "test-session"
        context.account.apiKey = "unvalidated-old-key"
        await context.account.restore()
        XCTAssertTrue(context.account.isSignedIn)
        XCTAssertEqual(
            context.account.apiKey,
            ""
        )
        XCTAssertEqual(
            context.account.errorMessage,
            "Try later"
        )
    }

    func testRestoreValidatesTheSessionAndKeepsAStillActiveSelectedKey() async throws {
        let context = makeContext(routes: [
            "/baas/api/user/info": #"{"success":true,"code":200,"data":{"uid":"user","nickname":"Tester"}}"#,
            "/baas/api/user/apikey/list": keysResponse,
        ])
        defer { context.cleanup() }
        context.store.value = "test-session"
        context.account.apiKey = "key-second"
        await context.account.restore()
        XCTAssertTrue(context.account.isSignedIn)
        XCTAssertEqual(
            context.account.displayName,
            "Tester"
        )
        XCTAssertEqual(
            context.account.apiKey,
            "key-second"
        )
        XCTAssertEqual(
            context.store.value,
            "test-session"
        )
    }

    func testTemporaryServiceFailurePreservesTheSessionForRetry() async {
        let context = makeContext(routes: [
            "/baas/api/user/info": #"{"success":false,"code":503,"message":"Try later","data":null}"#
        ])
        defer { context.cleanup() }
        context.store.value = "test-session"
        await context.account.restore()
        XCTAssertFalse(context.account.isSignedIn)
        XCTAssertTrue(context.account.hasSavedSession)
        XCTAssertEqual(
            context.store.value,
            "test-session"
        )
        XCTAssertEqual(
            context.account.errorMessage,
            "Try later"
        )
    }

    func testExplicitUnauthorizedRestorationClearsSessionAndSDKKey() async {
        let context = makeContext(routes: [
            "/baas/api/user/info": #"{"success":false,"code":401,"message":"Session expired","data":null}"#
        ])
        defer { context.cleanup() }
        context.store.value = "expired-test-session"
        context.account.apiKey = "previous-key"
        await context.account.restore()
        XCTAssertFalse(context.account.isSignedIn)
        XCTAssertFalse(context.account.hasSavedSession)
        XCTAssertNil(context.store.value)
        XCTAssertEqual(
            context.account.apiKey,
            ""
        )
        XCTAssertEqual(
            context.account.errorMessage,
            "Session expired"
        )
    }

    func testSignInDoesNotCreateKeysAndReplacesAnotherAccountsCredential() async throws {
        let context = makeContext(routes: [
            "/baas/api/user/login": #"{"success":true,"code":200,"data":"new-test-session"}"#,
            "/baas/api/user/info": #"{"success":true,"code":200,"data":{"uid":"new-user"}}"#,
            "/baas/api/user/apikey/list": keysResponse,
        ])
        defer { context.cleanup() }
        context.account.apiKey = "another-account-key"
        try await context.account.signIn(
            method: .sms,
            account: "13800000000",
            code: "123456",
            proof: CaptchaProof()
        )
        XCTAssertTrue(context.account.isSignedIn)
        XCTAssertEqual(
            context.store.value,
            "new-test-session"
        )
        XCTAssertEqual(
            context.account.apiKey,
            "key-first"
        )
        XCTAssertEqual(
            context.account.keys.count,
            2
        )
        XCTAssertNil(context.account.errorMessage)
    }

    func testLateLoginResponseCannotRecreateASignedOutSession() async throws {
        let context = makeContext(
            routes: [
                "/baas/api/user/login": #"{"success":true,"code":200,"data":"late-test-session"}"#,
                "/baas/api/user/info": #"{"success":true,"code":200,"data":{"uid":"user"}}"#,
                "/baas/api/user/apikey/list": keysResponse,
            ],
            delay: 0.08
        )
        defer { context.cleanup() }
        let login = _Concurrency.Task {
            try await context.account.signIn(
                method: .email,
                account: "test@example.invalid",
                code: "123456",
                proof: CaptchaProof()
            )
        }
        try await _Concurrency.Task.sleep(for: .milliseconds(10))
        try await context.account.signOut()
        do {
            try await login.value
            XCTFail("Expected the old operation to be rejected")
        } catch is CancellationError {
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(context.account.isSignedIn)
        XCTAssertNil(context.store.value)
        XCTAssertEqual(
            context.account.apiKey,
            ""
        )
    }

    func testNoKeysIsAValidSignedInStateWithoutAutomaticCreation() async throws {
        let context = makeContext(routes: [
            "/baas/api/user/login": #"{"success":true,"code":200,"data":"test-session"}"#,
            "/baas/api/user/info": #"{"success":true,"code":200,"data":{"uid":"user"}}"#,
            "/baas/api/user/apikey/list": #"{"success":true,"code":200,"data":[]}"#,
        ])
        defer { context.cleanup() }
        try await context.account.signIn(
            method: .sms,
            account: "13800000000",
            code: "123456",
            proof: CaptchaProof()
        )
        XCTAssertTrue(context.account.isSignedIn)
        XCTAssertTrue(context.account.keys.isEmpty)
        XCTAssertFalse(context.account.hasAPIKey)
        XCTAssertNil(context.account.errorMessage)
    }

    private var keysResponse: String {
        #"{"success":true,"code":200,"data":[{"uid":"first","tenantName":"open-platform","userUid":"user","name":"First","apiKey":"key-first","status":"active"},{"uid":"second","tenantName":"open-platform","userUid":"user","name":"Second","apiKey":"key-second","status":"active"}]}"#
    }

    private func makeContext(
        routes: [String: String],
        delay: Double = 0
    ) -> Context {
        let suite = "FaceNow.AccountTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = MemoryTokenStore()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountStubProtocol.self]
        let data = try! JSONEncoder().encode(routes)
        configuration.httpAdditionalHeaders = ["Stub-Routes": data.base64EncodedString(), "Stub-Delay": String(delay)]
        let client = NetworkRepository(
            session: Moya.Session(
                configuration: configuration,
                startRequestsImmediately: false
            )
        )
        return Context(
            client: client,
            store: store,
            account: UserRepository(
                defaults: defaults,
                client: client,
                store: store
            ),
            defaults: defaults,
            suite: suite
        )
    }

    private struct Context {

        let client: NetworkRepository
        let store: MemoryTokenStore
        let account: UserRepository
        let defaults: UserDefaults
        let suite: String
        func cleanup() { defaults.removePersistentDomain(forName: suite) }
    }
}

@MainActor
private final class MemoryTokenStore: UserTokenStoring {

    var value: String?
    func read() throws -> String? { value }
    func save(
        _ token: String
    ) throws { value = token }
    func remove() throws { value = nil }
}

private final class AccountStubProtocol: URLProtocol, @unchecked Sendable {

    private var responseTask: _Concurrency.Task<Void, Never>?
    override class func canInit(
        with request: URLRequest
    ) -> Bool { true }
    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest { request }
    override func startLoading() {
        let routes = try! JSONDecoder().decode(
            [String: String].self,
            from: Data(base64Encoded: request.value(forHTTPHeaderField: "Stub-Routes")!)!
        )
        let path = request.url!.path
        let delay = Double(request.value(forHTTPHeaderField: "Stub-Delay") ?? "0")!
        let body = routes[path] ?? #"{"success":false,"code":404,"message":"Unexpected test endpoint","data":null}"#
        responseTask = _Concurrency.Task {
            if delay > 0 { do { try await _Concurrency.Task.sleep(for: .seconds(delay)) } catch { return } }
            guard !_Concurrency.Task.isCancelled else { return }
            let response = HTTPURLResponse(
                url: self.request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            self.client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            self.client?.urlProtocol(
                self,
                didLoad: Data(body.utf8)
            )
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { responseTask?.cancel() }
}
