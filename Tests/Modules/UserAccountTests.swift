import Foundation
import Moya
import XCTest
import FNNetwork
import Storage
@testable import FNUser

@MainActor
final class UserAccountTests: XCTestCase {

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

    func testAPIKeySignInRequiresAnActiveRecordAndPublishesItsVerifiedOwner() async throws {
        let context = makeContext(routes: ["/baas/api/user/apikey/list": activeAPIKeyResponse])
        defer { context.cleanup() }
        try await context.account.signIn(apiKey: "  \(activeAPIKey)\n")
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

    func testAPIKeyRestorationMustRevalidateBeforeOpeningHome() async throws {
        let context = makeContext(
            routes: ["/baas/api/user/apikey/list": activeAPIKeyResponse],
            delay: 0.05
        )
        defer { context.cleanup() }
        context.store.value = activeAPIKey
        let restoration = _Concurrency.Task { await context.account.restore() }
        try await _Concurrency.Task.sleep(for: .milliseconds(10))
        XCTAssertTrue(context.account.isRestoring)
        XCTAssertFalse(context.account.canAccessHome)
        await restoration.value
        XCTAssertTrue(context.account.canAccessHome)
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
            routes: ["/baas/api/user/apikey/list": activeAPIKeyResponse],
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

    private var activeAPIKey: String {
        "uk-"
            + String(
                repeating: "a",
                count: 20
            )
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
