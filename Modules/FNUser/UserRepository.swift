//
//  UserRepository.swift
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
#if canImport(FNNetwork)
    import FNNetwork
#endif
#if canImport(Storage)
    import Storage
#endif

/// Coordinates account authentication, persisted sessions, and SDK-key selection.
@MainActor
final class UserRepository: ObservableObject {

    /// The profile validated for the current token.
    @Published private(set) var profile: AccountProfile?

    /// Whether the initial saved-session check is still running.
    @Published private(set) var isRestoring = false

    /// Whether an account request is in progress.
    @Published private(set) var isBusy = false

    /// Whether a key-list request is already in flight.
    @Published private(set) var isLoadingKeys = false

    /// A recoverable account error displayed in the form or account menu.
    @Published private(set) var errorMessage: String?

    /// The active API keys available to this signed-in user.
    @Published private(set) var keys: [APIKeyRecord] = []

    /// Whether a validated account session is available.
    var isSignedIn: Bool { profile != nil && token != nil }

    /// Home access requires a server-validated identity after saved-session restoration completes.
    var canAccessHome: Bool { isSignedIn && !isRestoring }

    /// Whether restoration can be retried without sending another verification code.
    var hasSavedSession: Bool { token != nil }

    /// A compact account label, avoiding plaintext API keys in the header.
    var displayName: String {
        if let name = profile?.nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        if let email = profile?.email, !email.isEmpty { return email }
        if let phone = profile?.phone, phone.count == 11 {
            return String(phone.prefix(3)) + "••••" + String(phone.suffix(4))
        }
        return isAPIKeySession ? "API Key" : "Account"
    }

    /// The platform repository resolved from the application container.
    @Injected(\.networkRepo) private var networkRepo: NetworkRepository

    /// The runtime SDK key persisted under the existing preference key.
    @Published var apiKey: String = "" {
        didSet {
            defaults.set(
                apiKey,
                forKey: Self.apiKeyDefaultsKey
            )
        }
    }

    /// Whether generation has a non-whitespace credential.
    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The existing persistence key shared with earlier application versions.
    private static let apiKeyDefaultsKey = "xmax.camera.apiKey"

    /// The preferences store can be overridden without changing process defaults.
    @Injected(\.userDefaults) private var defaults: UserDefaults

    /// The account token store, replaced by an in-memory implementation in tests.
    @Injected(\.userTokenStore) private var store: any UserTokenStoring

    /// The token retained in memory and never exposed to views or logs.
    private var token: String?

    /// Platform API keys have the documented uk- prefix; account tokens remain opaque JWT strings.
    private var isAPIKeySession: Bool { token?.hasPrefix("uk-") == true }

    /// Rejects late responses after logout or a newer sign-in operation.
    private var lifecycle = UUID()

    /// Creates account state without issuing requests or touching the camera.
    init(
        defaults: UserDefaults? = nil,
        client: NetworkRepository? = nil,
        store: (any UserTokenStoring)? = nil
    ) {
        if let defaults { self.defaults = defaults }
        if let client { self.networkRepo = client }
        if let store { self.store = store }
        _apiKey = Published(initialValue: self.defaults.string(forKey: Self.apiKeyDefaultsKey) ?? "")
    }

    /// Loads the tenant's verified sign-in capabilities without exposing transport to views.
    func loginConfiguration() async throws -> LoginConfiguration {
        try await networkRepo.send(
            AccountAPI.configuration,
            as: LoginConfiguration.self
        )
    }

    /// Sends a verification code with a fresh security proof supplied by the form.
    func sendCode(
        method: LoginMethod,
        account: String,
        proof: CaptchaProof
    ) async throws {
        _ = try await networkRepo.send(
            AccountAPI.sendCode(
                method: method,
                account: account,
                proof: proof
            ),
            as: EmptyResponse.self
        )
    }

    /// Validates the saved token, retaining it on transport or temporary service errors.
    func restore() async {
        guard !isBusy, !isRestoring else { return }
        isRestoring = true
        errorMessage = nil
        let operation = lifecycle
        defer { if lifecycle == operation { isRestoring = false } }
        do {
            token = try store.read()
            guard let token else { return }
            if isAPIKeySession {
                let records = try await networkRepo.send(
                    UserAPI.apiKeys,
                    as: [APIKeyRecord].self,
                    bearerToken: token
                )
                guard lifecycle == operation, !Task.isCancelled else { return }
                let record = try verifiedAPIKey(
                    token,
                    in: records
                )
                applyAPIKeySession(
                    token,
                    record: record,
                    records: records,
                    preferredKey: apiKey
                )
                return
            }
            let profile = try await networkRepo.send(
                AccountAPI.profile,
                as: AccountProfile.self,
                bearerToken: token
            )
            guard lifecycle == operation, !Task.isCancelled else { return }
            let preferredKey = apiKey
            apiKey = ""
            self.profile = profile
            await reloadKeys(preferredKey: preferredKey)
        } catch {
            guard lifecycle == operation, !Task.isCancelled else { return }
            await handleSessionError(error)
        }
    }

    /// Exchanges credentials and publishes only the profile belonging to this operation.
    func signIn(
        method: LoginMethod,
        account: String,
        code: String,
        proof: CaptchaProof
    ) async throws {
        guard !isBusy, !isRestoring else { return }
        isBusy = true
        errorMessage = nil
        let operation = UUID()
        lifecycle = operation
        defer { if lifecycle == operation { isBusy = false } }
        let endpoint = AccountAPI.login(
            method: method,
            account: account,
            code: code,
            proof: proof
        )
        let receivedToken = try await networkRepo.send(
            endpoint,
            as: String.self
        )
        guard lifecycle == operation, !Task.isCancelled else { throw CancellationError() }
        guard !receivedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkError.missingData
        }
        try store.save(receivedToken)
        token = receivedToken
        let receivedProfile: AccountProfile
        do {
            receivedProfile = try await networkRepo.send(
                AccountAPI.profile,
                as: AccountProfile.self,
                bearerToken: receivedToken
            )
        } catch {
            guard lifecycle == operation, !Task.isCancelled else { throw CancellationError() }
            await handleSessionError(error)
            throw error
        }
        guard lifecycle == operation, !Task.isCancelled else { throw CancellationError() }
        // A key from a different account must never reach the SDK while the new list loads.
        apiKey = ""
        keys = []
        await reloadKeys()
        guard lifecycle == operation, !Task.isCancelled else { throw CancellationError() }
        profile = receivedProfile
    }

    /// Signs in with an API key only after the platform confirms its active owner record.
    func signIn(
        apiKey value: String
    ) async throws {
        guard !isBusy, !isRestoring, !isLoadingKeys else { return }
        let credential = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard credential.hasPrefix("uk-"), credential.count > 3 else {
            throw NetworkError.server(
                code: 400,
                message: "Enter a valid API key beginning with uk-."
            )
        }
        isBusy = true
        errorMessage = nil
        let operation = UUID()
        lifecycle = operation
        defer { if lifecycle == operation { isBusy = false } }
        let records = try await networkRepo.send(
            UserAPI.apiKeys,
            as: [APIKeyRecord].self,
            bearerToken: credential
        )
        guard lifecycle == operation, !Task.isCancelled else { throw CancellationError() }
        let record = try verifiedAPIKey(
            credential,
            in: records
        )
        try store.save(credential)
        applyAPIKeySession(
            credential,
            record: record,
            records: records,
            preferredKey: credential
        )
    }

    /// Finds the exact active key and its tenant-scoped identity rather than trusting a nonempty input.
    private func verifiedAPIKey(
        _ credential: String,
        in records: [APIKeyRecord]
    ) throws -> APIKeyRecord {
        guard
            let record = records.first(where: {
                $0.apiKey == credential && $0.status == "active" && $0.tenantName == AccountAPI.tenant
                    && !$0.userUid.isEmpty
            })
        else {
            throw NetworkError.server(
                code: 401,
                message: "This API key is invalid or no longer active."
            )
        }
        return record
    }

    /// Publishes only identity and keys confirmed by the authenticated API-key response.
    private func applyAPIKeySession(
        _ credential: String,
        record: APIKeyRecord,
        records: [APIKeyRecord],
        preferredKey: String
    ) {
        token = credential
        keys = records.filter {
            $0.status == "active" && $0.userUid == record.userUid && $0.tenantName == record.tenantName
                && !$0.apiKey.isEmpty
        }
        apiKey = keys.first(where: { $0.apiKey == preferredKey })?.apiKey ?? credential
        var identity = AccountProfile()
        identity.uid = record.userUid
        profile = identity
        errorMessage = nil
    }

    /// Loads this user's keys and keeps a still-valid selection stable.
    func reloadKeys(
        preferredKey: String? = nil
    ) async {
        guard let token, !isLoadingKeys else { return }
        isLoadingKeys = true
        let operation = lifecycle
        defer { if lifecycle == operation { isLoadingKeys = false } }
        do {
            let records = try await networkRepo.send(
                UserAPI.apiKeys,
                as: [APIKeyRecord].self,
                bearerToken: token
            )
            guard lifecycle == operation, !Task.isCancelled else { return }
            if isAPIKeySession {
                _ = try verifiedAPIKey(
                    token,
                    in: records
                )
            }
            keys = records.filter { $0.status == "active" && !$0.apiKey.isEmpty }
            let selected = preferredKey ?? apiKey
            apiKey = keys.first(where: { $0.apiKey == selected })?.apiKey ?? keys.first?.apiKey ?? ""
            errorMessage = nil
        } catch {
            guard lifecycle == operation, !Task.isCancelled else { return }
            await handleSessionError(error)
        }
    }

    /// Creates a FaceNow key only after the user chooses the account-menu action.
    func createKey() async {
        guard let token, !isBusy, !isLoadingKeys else { return }
        isBusy = true
        let operation = lifecycle
        defer { if lifecycle == operation { isBusy = false } }
        do {
            let record = try await networkRepo.send(
                UserAPI.createAPIKey(name: "FaceNow"),
                as: APIKeyRecord.self,
                bearerToken: token
            )
            guard lifecycle == operation, !Task.isCancelled else { return }
            keys.insert(
                record,
                at: 0
            )
            apiKey = record.apiKey
            errorMessage = nil
        } catch {
            guard lifecycle == operation, !Task.isCancelled else { return }
            await handleSessionError(error)
        }
    }

    /// Selects only a key present in the current user's latest active-key list.
    func selectKey(
        uid: String
    ) {
        guard let record = keys.first(where: { $0.uid == uid }), isSignedIn else { return }
        apiKey = record.apiKey
    }

    /// Clears the local session before making a best-effort server logout request.
    func signOut() async throws {
        let previous = isAPIKeySession ? nil : token
        try store.remove()
        reset()
        if let previous {
            _ = try? await networkRepo.send(
                AccountAPI.logout,
                as: EmptyResponse.self,
                bearerToken: previous
            )
        }
    }

    /// Invalidates pending account work during application shutdown.
    func cancelPendingOperations() {
        lifecycle = UUID()
        isBusy = false
        isRestoring = false
        isLoadingKeys = false
    }

    /// Clears session state only when the service explicitly rejects authentication.
    private func handleSessionError(
        _ error: Error
    ) async {
        if let failure = error as? NetworkError, failure.isUnauthorized {
            do { try store.remove() } catch {
                reset()
                errorMessage = error.localizedDescription
                return
            }
            reset()
        }
        errorMessage = error.localizedDescription
    }

    /// Makes stale requests harmless and clears SDK credentials with the account.
    private func reset() {
        lifecycle = UUID()
        token = nil
        profile = nil
        keys = []
        apiKey = ""
        isBusy = false
        isRestoring = false
        isLoadingKeys = false
        errorMessage = nil
    }
}

extension Container {

    /// The shared User repository registered for this container.
    @MainActor
    var userRepo: Factory<UserRepository> {
        Factory(self) { @MainActor in UserRepository() }.singleton
    }
}
