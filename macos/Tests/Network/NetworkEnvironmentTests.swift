import Foundation
import XCTest
@testable import FNNetwork

final class NetworkEnvironmentTests: XCTestCase {

    func testDefaultAccountAndAPIKeyOriginsMatchTheApplicationEdition() throws {
        #if OVERSEA
            let expectedHost = "api.xmax.cloud"
        #else
            let expectedHost = "cloud.xmax.22duck.cn"
        #endif
        let client = NetworkRepository()
        let configuration = try client.request(for: AccountAPI.configuration)
        let keys = try client.request(for: UserAPI.apiKeys, bearerToken: "test-session")
        XCTAssertEqual(configuration.url?.host, expectedHost)
        XCTAssertEqual(keys.url?.host, expectedHost)
        XCTAssertEqual(AccountAPI.configuration.baseURL.host, expectedHost)
        XCTAssertEqual(UserAPI.apiKeys.baseURL.host, expectedHost)
        XCTAssertEqual(configuration.url?.scheme, "https")
    }

    func testRegionalClientsKeepAccountKeysAndCreditsOnTheSameOrigin() throws {
        for (environment, host) in [(NetworkEnvironment.china, "cloud.xmax.22duck.cn"), (.global, "api.xmax.cloud")] {
            let client = NetworkRepository(baseURL: environment.baseURL)
            let configuration = try client.request(for: AccountAPI.configuration)
            XCTAssertEqual(configuration.url?.host, host)
            XCTAssertEqual(configuration.url?.path, "/baas/api/user/login/config")
            XCTAssertEqual(
                URLComponents(url: configuration.url!, resolvingAgainstBaseURL: false)?.queryItems,
                [URLQueryItem(name: "tenantName", value: "open-platform")]
            )
            XCTAssertNil(configuration.value(forHTTPHeaderField: "Authorization"))
            for (endpoint, path) in [(AccountAPI.profile, "/baas/api/user/info"), (.balance, "/open/api/v1/points/balance")] {
                let request = try client.request(for: endpoint, bearerToken: "test-session")
                XCTAssertEqual(request.url?.host, host)
                XCTAssertEqual(request.url?.path, path)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-session")
            }
            let keys = try client.request(for: UserAPI.apiKeys, bearerToken: "test-session")
            XCTAssertEqual(keys.url?.host, host)
            XCTAssertEqual(keys.url?.path, "/baas/api/user/apikey/list")
            XCTAssertEqual(keys.value(forHTTPHeaderField: "Authorization"), "Bearer test-session")
        }
    }

    func testInjectedOriginOverridesTheTargetDefaultForAuthenticatedRequests() throws {
        let client = NetworkRepository(baseURL: URL(string: "https://network.example")!)
        let request = try client.request(for: AccountAPI.profile, bearerToken: "test-session")
        XCTAssertEqual(request.url?.host, "network.example")
        XCTAssertEqual(request.url?.path, "/baas/api/user/info")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-session")
    }
}
