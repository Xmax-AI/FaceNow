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
import CryptoKit
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

    /// The account credit page opened from the header balance.
    let creditsURL = URL(string: "https://platform.xmax.ai/credits")!

    /// The account usage page opened from the profile card.
    let usageURL = URL(string: "https://platform.xmax.ai/usage")!

    /// Reports explicit, validated sign-ins without replaying saved-session restoration.
    var signInCompleted: AnyPublisher<Void, Never> { signInEvents.eraseToAnyPublisher() }

    /// Emits only after a manual login has committed its authenticated identity.
    private let signInEvents = PassthroughSubject<Void, Never>()

    /// Distinguishes cached home presentation from a server-verified session.
    private enum SessionState {

        /// No session may currently open home.
        case signedOut

        /// A Keychain credential permits immediate home presentation while validation runs.
        case cached

        /// The server has confirmed the current identity.
        case verified
    }

    /// The navigation state, independent of background request progress.
    @Published private var sessionState = SessionState.signedOut

    /// A transient login-page notification after background validation fails.
    @Published private(set) var sessionNotice: String?

    /// A presentation snapshot bound to the credential without copying its plaintext into preferences.
    private struct CachedSession: Codable {

        /// The SHA-256 digest used to reject another session's profile snapshot.
        let credentialDigest: String

        /// The last server-confirmed account details.
        let profile: AccountProfile
    }

    /// The preferences key for the cached profile and credential digest.
    private static let profileCacheKey = "xmax.camera.accountProfile"

    /// The current profile, initially loaded from a matching local snapshot when available.
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

    /// The last server-confirmed credit balance; nil means it has not been obtained.
    @Published private(set) var remainingCredits: Double?

    /// Whether a balance request is already in flight.
    @Published private(set) var isLoadingCredits = false

    /// A balance-specific failure that preserves the last confirmed value.
    @Published private(set) var creditsErrorMessage: String?

    /// The last attempted balance refresh, measured independently of wall-clock changes.
    private var creditsRefreshedAt: ContinuousClock.Instant?

    /// Whether a validated account session is available.
    var isSignedIn: Bool { profile != nil && token != nil }

    /// A saved Keychain session opens home immediately, including migration from versions without profile caching.
    var canAccessHome: Bool { token != nil && sessionState != .signedOut }

    /// Billable generation waits for background identity verification to finish.
    var hasVerifiedSession: Bool { isSignedIn && sessionState == .verified && !isRestoring }

    /// Whether restoration can be retried without sending another verification code.
    var hasSavedSession: Bool { token != nil }

    /// The final four characters of an API-key login credential, without exposing the full key.
    var sessionAPIKeySuffix: String? {
        guard isAPIKeySession, let token else { return nil }
        return token.count > 4 ? String(token.suffix(4)) : ""
    }

    /// A compact account label, avoiding plaintext API keys in the header.
    var displayName: String {
        if let name = profile?.nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        if let email = profile?.email, !email.isEmpty { return email }
        if let phone = profile?.phone, phone.count == 11 {
            return String(phone.prefix(3)) + "••••" + String(phone.suffix(4))
        }
        return isAPIKeySession ? UserStrings.apiKey : AccountStrings.accountAccount
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
        // Read before the first render so saved accounts never mount the login page on startup.
        token = try? self.store.read()
        if let token {
            sessionState = .cached
            if let data = self.defaults.data(forKey: Self.profileCacheKey),
                let cached = try? JSONDecoder().decode(CachedSession.self, from: data),
                cached.credentialDigest == Self.credentialDigest(token)
            {
                profile = cached.profile
            } else {
                self.defaults.removeObject(forKey: Self.profileCacheKey)
            }
        } else {
            self.defaults.removeObject(forKey: Self.profileCacheKey)
        }
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

    /// Refreshes cached identity in the background and returns failed sessions to login with a notice.
    func restore() async {
        guard !isBusy, !isRestoring else { return }
        isRestoring = true
        errorMessage = nil
        let operation = lifecycle
        defer { if lifecycle == operation { isRestoring = false } }
        do {
            token = try store.read()
            guard let token else {
                reset()
                return
            }
            sessionState = .cached
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
                let profile = try await loadAPIKeyProfile(
                    token,
                    record: record
                )
                guard lifecycle == operation, !Task.isCancelled else { return }
                applyAPIKeySession(
                    token,
                    profile: profile,
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
            commitProfile(profile)
            await reloadKeys(preferredKey: preferredKey)
        } catch {
            guard lifecycle == operation, !Task.isCancelled else { return }
            await handleSessionError(error)
            // A temporary failure retains the Keychain credential but must still leave the cached home.
            sessionState = .signedOut
            profile = nil
            keys = []
            apiKey = ""
            clearCredits()
            defaults.removeObject(forKey: Self.profileCacheKey)
            sessionNotice =
                (error as? NetworkError)?.isUnauthorized == true
                ? AccountStrings.sessionExpired
                : AccountStrings.sessionUnavailable
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
        clearCredits()
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
        defaults.removeObject(forKey: Self.profileCacheKey)
        profile = nil
        sessionState = .signedOut
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
        commitProfile(receivedProfile)
        signInEvents.send()
    }

    /// Signs in only after the platform confirms the active key and its owner's profile.
    func signIn(
        apiKey value: String
    ) async throws {
        guard !isBusy, !isRestoring, !isLoadingKeys else { return }
        let credential = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard credential.hasPrefix("uk-"), credential.count > 3 else {
            throw NetworkError.server(
                code: 400,
                message: AccountStrings.invalidAPIKey
            )
        }
        isBusy = true
        errorMessage = nil
        let operation = UUID()
        lifecycle = operation
        clearCredits()
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
        let profile = try await loadAPIKeyProfile(
            credential,
            record: record
        )
        guard lifecycle == operation, !Task.isCancelled else { throw CancellationError() }
        try store.save(credential)
        applyAPIKeySession(
            credential,
            profile: profile,
            record: record,
            records: records,
            preferredKey: credential
        )
        signInEvents.send()
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
                message: AccountStrings.inactiveAPIKey
            )
        }
        return record
    }

    /// Requires a complete profile response whose identity matches the verified key owner.
    private func loadAPIKeyProfile(
        _ credential: String,
        record: APIKeyRecord
    ) async throws -> AccountProfile {
        let profile = try await networkRepo.send(
            AccountAPI.profile,
            as: AccountProfile.self,
            bearerToken: credential
        )
        let owner = profile.uid?.isEmpty == false ? profile.uid : profile.id
        guard owner == record.userUid else {
            throw NetworkError.server(
                code: 401,
                message: AccountStrings.ownerMismatch
            )
        }
        return profile
    }

    /// Publishes only identity and keys confirmed by the authenticated API-key response.
    private func applyAPIKeySession(
        _ credential: String,
        profile: AccountProfile,
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
        commitProfile(profile)
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

    /// Refreshes server-owned credits without changing the active generation key.
    func refreshCredits(
        force: Bool = false
    ) async {
        guard hasVerifiedSession, let token, !isBusy, !isLoadingCredits else { return }
        let now = ContinuousClock.now
        if !force, let creditsRefreshedAt, now - creditsRefreshedAt < .seconds(5) { return }
        creditsRefreshedAt = now
        isLoadingCredits = true
        let operation = lifecycle
        defer { if lifecycle == operation { isLoadingCredits = false } }
        do {
            let balance = try await networkRepo.send(
                AccountAPI.balance,
                as: AccountBalance.self,
                bearerToken: token
            )
            guard lifecycle == operation, !Task.isCancelled else { return }
            remainingCredits = balance.currentBalance
            creditsErrorMessage = nil
        } catch {
            guard lifecycle == operation, !Task.isCancelled else { return }
            creditsErrorMessage = error.localizedDescription
        }
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
        isLoadingCredits = false
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
            sessionNotice = AccountStrings.sessionExpired
        }
        errorMessage = error.localizedDescription
    }

    /// Dismisses the transient authentication notice without altering form layout.
    func dismissSessionNotice() { sessionNotice = nil }

    /// Publishes and persists only a profile obtained with the current credential.
    private func commitProfile(
        _ profile: AccountProfile
    ) {
        guard let token else { return }
        self.profile = profile
        sessionState = .verified
        sessionNotice = nil
        let cached = CachedSession(
            credentialDigest: Self.credentialDigest(token),
            profile: profile
        )
        if let data = try? JSONEncoder().encode(cached) {
            defaults.set(data, forKey: Self.profileCacheKey)
        }
    }

    /// Associates cached display data with a credential without persisting the credential itself.
    private static func credentialDigest(
        _ credential: String
    ) -> String {
        Data(SHA256.hash(data: Data(credential.utf8))).base64EncodedString()
    }

    /// Removes the previous account's balance and invalidates its refresh state.
    private func clearCredits() {
        remainingCredits = nil
        creditsErrorMessage = nil
        creditsRefreshedAt = nil
        isLoadingCredits = false
    }

    /// Makes stale requests harmless and clears SDK credentials with the account.
    private func reset() {
        lifecycle = UUID()
        token = nil
        profile = nil
        sessionState = .signedOut
        sessionNotice = nil
        defaults.removeObject(forKey: Self.profileCacheKey)
        keys = []
        clearCredits()
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
