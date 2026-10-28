//
//  UserTokenStore.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
import Security

/// Persists the authenticated session credential independently of SDK API-key preferences.
@MainActor
public protocol UserTokenStoring {

    /// Reads a previously saved token, if one exists.
    func read() throws -> String?

    /// Replaces the stored token after a successful credential exchange.
    func save(
        _ token: String
    ) throws

    /// Removes the stored account session.
    func remove() throws
}

/// Stores the domestic session token or verified API key in the application's private Keychain item.
@MainActor
public struct UserTokenStore: UserTokenStoring {

    /// Scopes the item to the domestic tenant and avoids mixing service environments.
    private let service = "com.xmax.meeting.camera.account.cloud.xmax.22duck.cn.open-platform"

    /// Creates the account-token service without accessing Keychain.
    public init() {}

    /// Builds the stable Keychain identity without placing tokens in preferences.
    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: "session",
        ]
    }

    /// Reads the session without prompting for biometric authentication.
    public func read() throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(
            query as CFDictionary,
            &item
        )
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
            let token = String(
                data: data,
                encoding: .utf8
            ), !token.isEmpty
        else {
            throw TokenError(status: status)
        }
        return token
    }

    /// Updates an existing item atomically or creates a device-local item.
    public func save(
        _ token: String
    ) throws {
        let attributes = [kSecValueData as String: Data(token.utf8)]
        let updated = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw TokenError(status: updated) }
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(
            item as CFDictionary,
            nil
        )
        guard status == errSecSuccess else { throw TokenError(status: status) }
    }

    /// Deletes the session without treating an absent item as a failure.
    public func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TokenError(status: status) }
    }

    /// Describes storage failure without including the token or account identity.
    private struct TokenError: LocalizedError {

        /// The OSStatus returned by Security.framework.
        let status: OSStatus

        /// A concise recovery hint displayed by the account flow.
        var errorDescription: String? {
            "Unable to access the saved session in Keychain (\(status)). Please try again."
        }
    }
}
