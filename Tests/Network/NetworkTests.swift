import Foundation
import Moya
import XCTest
@testable import FNNetwork

final class NetworkTests: XCTestCase {

    func testHandyJSONDefaultsCannotReplaceMissingSecurityConfiguration() async throws {
        let client = makeClient(
            status: 200,
            json: #"{"success":true,"code":200,"data":{"tenantName":"open-platform"}}"#
        )
        do {
            _ = try await client.send(
                AccountAPI.configuration,
                as: LoginConfiguration.self
            )
            XCTFail("Expected incomplete security settings to be rejected")
        } catch {
            guard case NetworkError.invalidResponse = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testHandyJSONRejectsMalformedKeyRecordsWithoutSilentlyDroppingThem() async throws {
        let client = makeClient(
            status: 200,
            json:
                #"{"success":true,"code":200,"data":[{"uid":"valid","tenantName":"open-platform","userUid":"user","name":"First","apiKey":"test-key","status":"active"},{"uid":"missing-key"}]}"#
        )
        do {
            _ = try await client.send(
                UserAPI.apiKeys,
                as: [APIKeyRecord].self,
                bearerToken: "token"
            )
            XCTFail("Expected the malformed record to reject the entire list")
        } catch {
            guard case NetworkError.invalidResponse = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testTaskCancellationStopsTheUnderlyingMoyaRequest() async throws {
        let identifier = UUID().uuidString
        let started = expectation(description: "Moya started the request")
        let stopped = expectation(description: "Moya cancelled the URL loading operation")
        let center = NotificationCenter.default
        let startObserver = center.addObserver(
            forName: Notification.Name("FaceNow.RequestStarted." + identifier),
            object: nil,
            queue: nil
        ) { _ in started.fulfill() }
        let stopObserver = center.addObserver(
            forName: Notification.Name("FaceNow.RequestStopped." + identifier),
            object: nil,
            queue: nil
        ) { _ in stopped.fulfill() }
        defer {
            center.removeObserver(startObserver)
            center.removeObserver(stopObserver)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CancellationProtocol.self]
        configuration.httpAdditionalHeaders = ["Cancellation-ID": identifier]
        let client = NetworkRepository(
            session: Moya.Session(
                configuration: configuration,
                startRequestsImmediately: false
            )
        )
        let request = _Concurrency.Task {
            try await client.send(
                UserAPI.apiKeys,
                as: [APIKeyRecord].self,
                bearerToken: "test-token"
            )
        }
        await fulfillment(
            of: [started],
            timeout: 2
        )
        request.cancel()
        do {
            _ = try await request.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {} catch {
            XCTFail("Unexpected error: \(error)")
        }
        await fulfillment(
            of: [stopped],
            timeout: 2
        )
    }

    func testDomesticLoginUsesOpenPlatformTenantAndCamelCaseCredentials() throws {
        let client = NetworkRepository()
        let endpoint = AccountAPI.login(
            method: .sms,
            account: "13800000000",
            code: "123456",
            proof: CaptchaProof(
                ticket: "test-ticket",
                randomString: "test-random"
            )
        )
        let request = try client.request(for: endpoint)
        XCTAssertEqual(
            request.url?.path,
            "/baas/api/user/login"
        )
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(
            body,
            [
                "tenantName": "open-platform", "loginMethod": "sms", "accountName": "13800000000",
                "credential": "123456", "captchaTicket": "test-ticket", "captchaRandStr": "test-random",
            ]
        )
    }

    func testCodeDestinationsUseSeparateRoutesAndNeverSendTheOtherAccountField() throws {
        let client = NetworkRepository()
        for method in LoginMethod.allCases {
            let request = try client.request(
                for: AccountAPI.sendCode(
                    method: method,
                    account: "test-destination",
                    proof: CaptchaProof()
                )
            )
            let route = method == .sms ? "sms-code" : "email-code"
            XCTAssertEqual(
                request.url?.path,
                "/baas/api/message/public/\(route)/send"
            )
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String]
            )
            XCTAssertEqual(
                body,
                ["tenantName": "open-platform", method == .sms ? "phone" : "email": "test-destination"]
            )
        }
    }

    func testConfigurationUsesTenantQueryAndRespectsServiceCodeLengths() async throws {
        let client = makeClient(
            status: 200,
            json:
                #"{"success":true,"code":200,"data":{"tenantName":"open-platform","enableSmsLogin":true,"enableEmailLogin":false,"enableCaptcha":true,"captchaRequiredOnLogin":true,"captchaAppId":"test","smsCodeLength":4,"emailCodeLength":6,"smsCodeCooldownSeconds":45,"emailCodeCooldownSeconds":60}}"#
        )
        let endpoint = AccountAPI.configuration
        let request = try client.request(for: endpoint)
        XCTAssertEqual(
            URLComponents(
                url: request.url!,
                resolvingAgainstBaseURL: false
            )?.queryItems,
            [
                URLQueryItem(
                    name: "tenantName",
                    value: "open-platform"
                )
            ]
        )
        let configuration = try await client.send(
            endpoint,
            as: LoginConfiguration.self
        )
        XCTAssertTrue(configuration.supports(.sms))
        XCTAssertFalse(configuration.supports(.email))
        XCTAssertEqual(
            configuration.codeLength(for: .sms),
            4
        )
        XCTAssertEqual(
            configuration.cooldown(for: .sms),
            45
        )
    }

    func testRequestKeepsAuthorizationOutOfTheURLAndEncodesDeleteQuery() throws {
        let request = try NetworkRepository().request(
            for: UserAPI.deleteAPIKey(uid: "record+id&other=value"),
            bearerToken: "  test-token\n"
        )
        XCTAssertEqual(
            request.httpMethod,
            "DELETE"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer test-token"
        )
        let components = try XCTUnwrap(
            URLComponents(
                url: try XCTUnwrap(request.url),
                resolvingAgainstBaseURL: false
            )
        )
        XCTAssertEqual(
            components.path,
            "/baas/api/user/apikey/delete"
        )
        XCTAssertEqual(
            components.queryItems,
            [
                URLQueryItem(
                    name: "uid",
                    value: "record+id&other=value"
                )
            ]
        )
        XCTAssertNil(request.httpBody)
        XCTAssertFalse(try XCTUnwrap(request.url).absoluteString.contains("test-token"))
    }

    func testCreateAndRenameUseDocumentedBodiesAndTrimNames() throws {
        let client = NetworkRepository()
        let create = try client.request(
            for: UserAPI.createAPIKey(name: " FaceNow "),
            bearerToken: "token"
        )
        XCTAssertEqual(
            create.httpMethod,
            "POST"
        )
        XCTAssertEqual(
            create.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: XCTUnwrap(create.httpBody)) as? [String: String],
            ["name": "FaceNow"]
        )
        let update = try client.request(
            for: UserAPI.renameAPIKey(
                uid: "record",
                name: "New name"
            ),
            bearerToken: "token"
        )
        XCTAssertEqual(
            update.httpMethod,
            "PUT"
        )
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: XCTUnwrap(update.httpBody)) as? [String: String],
            ["uid": "record", "name": "New name"]
        )
        XCTAssertThrowsError(
            try client.request(
                for: UserAPI.createAPIKey(name: " \n"),
                bearerToken: "token"
            )
        )
        XCTAssertThrowsError(
            try client.request(
                for: UserAPI.createAPIKey(
                    name: String(
                        repeating: "x",
                        count: 17
                    )
                ),
                bearerToken: "token"
            )
        )
    }

    func testMissingCredentialFailsBeforeTransport() throws {
        XCTAssertThrowsError(try NetworkRepository().request(for: UserAPI.apiKeys)) { error in
            guard case NetworkError.missingCredential = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testSuccessfulListDecodesTheKeyRecord() async throws {
        let client = makeClient(
            status: 200,
            json: """
                {"success":true,"code":200,"data":[{"uid":"record","tenantName":"open-platform","userUid":"user","name":"FaceNow","apiKey":"test-only-key","status":"active"}]}
                """
        )
        let keys = try await client.send(
            UserAPI.apiKeys,
            as: [APIKeyRecord].self,
            bearerToken: "token"
        )
        XCTAssertEqual(
            keys.map(\.uid),
            ["record"]
        )
        XCTAssertEqual(
            keys.first?.apiKey,
            "test-only-key"
        )
    }

    func testBusinessErrorIsPreservedEvenWhenDataCannotDecode() async throws {
        let client = makeClient(
            status: 200,
            json: """
                {"success":false,"code":46002,"message":"Expired token","data":{"unexpected":true}}
                """
        )
        do {
            _ = try await client.send(
                UserAPI.apiKeys,
                as: [APIKeyRecord].self,
                bearerToken: "token"
            )
            XCTFail("Expected rejection")
        } catch let error as NetworkError {
            XCTAssertTrue(error.isUnauthorized)
            XCTAssertEqual(
                error.localizedDescription,
                "Expired token"
            )
        }
    }

    func testHTTPUnauthorizedCannotBeOverriddenByASuccessEnvelope() async throws {
        let client = makeClient(
            status: 401,
            json: """
                {"success":true,"code":200,"data":[]}
                """
        )
        do {
            _ = try await client.send(
                UserAPI.apiKeys,
                as: [APIKeyRecord].self,
                bearerToken: "token"
            )
            XCTFail("Expected rejection")
        } catch let error as NetworkError {
            XCTAssertTrue(error.isUnauthorized)
        }
    }

    func testNullDeleteDataSucceedsButNullListIsRejected() async throws {
        let client = makeClient(
            status: 200,
            json: """
                {"success":true,"code":200,"data":null}
                """
        )
        _ = try await client.send(
            UserAPI.deleteAPIKey(uid: "record"),
            as: EmptyResponse.self,
            bearerToken: "token"
        )
        do {
            _ = try await client.send(
                UserAPI.apiKeys,
                as: [APIKeyRecord].self,
                bearerToken: "token"
            )
            XCTFail("Expected required payload")
        } catch {
            guard case NetworkError.missingData = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testMalformedSuccessResponseIsRejected() async throws {
        let client = makeClient(
            status: 200,
            json: "<html>Unavailable</html>"
        )
        do {
            _ = try await client.send(
                UserAPI.apiKeys,
                as: [APIKeyRecord].self,
                bearerToken: "token"
            )
            XCTFail("Expected JSON failure")
        } catch {
            guard case NetworkError.invalidResponse = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    private func makeClient(
        status: Int,
        json: String
    ) -> NetworkRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        configuration.httpAdditionalHeaders = [
            "Stub-Status": String(status), "Stub-Body": Data(json.utf8).base64EncodedString(),
        ]
        return NetworkRepository(
            session: Moya.Session(
                configuration: configuration,
                startRequestsImmediately: false
            )
        )
    }
}

private final class CancellationProtocol: URLProtocol, @unchecked Sendable {

    override class func canInit(
        with request: URLRequest
    ) -> Bool { true }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest { request }

    override func startLoading() {
        NotificationCenter.default.post(
            name: Notification.Name("FaceNow.RequestStarted." + request.value(forHTTPHeaderField: "Cancellation-ID")!),
            object: nil
        )
    }

    override func stopLoading() {
        NotificationCenter.default.post(
            name: Notification.Name("FaceNow.RequestStopped." + request.value(forHTTPHeaderField: "Cancellation-ID")!),
            object: nil
        )
    }
}

private final class StubProtocol: URLProtocol, @unchecked Sendable {

    override class func canInit(
        with request: URLRequest
    ) -> Bool { true }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest { request }

    override func startLoading() {
        let status = Int(request.value(forHTTPHeaderField: "Stub-Status") ?? "200")!
        let data = Data(base64Encoded: request.value(forHTTPHeaderField: "Stub-Body")!)!
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(
            self,
            didLoad: data
        )
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
