import Factory
import Foundation
import XCTest
import FNNetwork
import Storage
@testable import FNUser

@MainActor
final class RepositoryInjectionTests: XCTestCase {

    func testInjectedConsumersShareUserDataAndUseRegisteredStorage() async {
        let suite = "FaceNow.InjectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = InjectedTokenStore()
        let container = Container()
        await Container.$shared.withValue(container) {
            await Scope.$singleton.withValue(Scope.Singleton()) {
                container.userDefaults.register { @MainActor in defaults }
                container.userTokenStore.register { @MainActor in store }
                let editor = InjectedUserConsumer()
                let generation = InjectedUserConsumer()
                XCTAssertTrue(editor.userRepo === generation.userRepo)
                editor.userRepo.apiKey = "isolated-test-key"
                XCTAssertEqual(
                    generation.userRepo.apiKey,
                    "isolated-test-key"
                )
                XCTAssertEqual(
                    defaults.string(forKey: "xmax.camera.apiKey"),
                    "isolated-test-key"
                )
                await generation.userRepo.restore()
                XCTAssertEqual(
                    store.readCount,
                    1
                )
                XCTAssertFalse(generation.userRepo.hasSavedSession)
            }
        }
    }

    func testNetworkOverrideIsResolvedByAnnotationWithoutSendingARequest() async throws {
        let repository = NetworkRepository(baseURL: URL(string: "https://injection.example")!)
        let container = Container()
        try Container.$shared.withValue(container) {
            try Scope.$singleton.withValue(Scope.Singleton()) {
                container.networkRepo.register { repository }
                let consumer = InjectedNetworkConsumer()
                XCTAssertTrue(consumer.networkRepo === repository)
                let request = try consumer.networkRepo.request(for: AccountAPI.configuration)
                XCTAssertEqual(
                    request.url?.host,
                    "injection.example"
                )
            }
        }
    }

    func testFreshScopesDoNotReuseAnotherUsersRepository() async {
        let first = Container.$shared.withValue(Container()) {
            Scope.$singleton.withValue(Scope.Singleton()) { InjectedUserConsumer().userRepo }
        }
        let second = Container.$shared.withValue(Container()) {
            Scope.$singleton.withValue(Scope.Singleton()) { InjectedUserConsumer().userRepo }
        }
        XCTAssertFalse(first === second)
    }
}

@MainActor
private struct InjectedUserConsumer {

    @Injected(\.userRepo) var userRepo: UserRepository
}

private struct InjectedNetworkConsumer {

    @Injected(\.networkRepo) var networkRepo: NetworkRepository
}

@MainActor
private final class InjectedTokenStore: UserTokenStoring {

    private(set) var readCount = 0
    func read() throws -> String? {
        readCount += 1
        return nil
    }
    func save(
        _ token: String
    ) throws {}
    func remove() throws {}
}
