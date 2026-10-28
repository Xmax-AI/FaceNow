//
//  UserAPI.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
@preconcurrency import Moya

/// Describes the current user's API-key operations as Moya targets.
public enum UserAPI: APITargetType {

    /// Lists active keys in the server's newest-first order.
    case apiKeys

    /// Creates a named credential after validating the platform's name constraints.
    case createAPIKey(name: String)

    /// Renames an existing key without replacing its credential.
    case renameAPIKey(uid: String, name: String)

    /// Deletes a key using its documented query parameter.
    case deleteAPIKey(uid: String)

    /// The service-relative route used by the selected operation.
    public var path: String {
        let suffix: String
        switch self {
        case .apiKeys: suffix = "list"
        case .createAPIKey: suffix = "create"
        case .renameAPIKey: suffix = "update"
        case .deleteAPIKey: suffix = "delete"
        }
        return "/baas/api/user/apikey/\(suffix)"
    }

    /// The HTTP verb required by each API-key operation.
    public var method: Moya.Method {
        switch self {
        case .apiKeys: return .get
        case .createAPIKey: return .post
        case .renameAPIKey: return .put
        case .deleteAPIKey: return .delete
        }
    }

    /// Maps mutable key fields through HandyJSON and puts DELETE identifiers in the URL.
    public var task: Moya.Task {
        switch self {
        case .apiKeys: return .requestPlain
        case .deleteAPIKey(let uid):
            return .requestParameters(
                parameters: ["uid": uid],
                encoding: URLEncoding.queryString
            )
        case .createAPIKey(let name):
            var request = APIKeyRequest()
            request.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return .requestParameters(
                parameters: request.toJSON() ?? [:],
                encoding: JSONEncoding.default
            )
        case .renameAPIKey(
            let uid,
            let name
        ):
            var request = APIKeyRequest()
            request.uid = uid
            request.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return .requestParameters(
                parameters: request.toJSON() ?? [:],
                encoding: JSONEncoding.default
            )
        }
    }

    /// Every key operation is scoped to an explicitly authenticated caller.
    public var requiresAuthorization: Bool { true }

    /// Rejects invalid key names before Moya creates a network operation.
    public func validate() throws {
        let name: String
        switch self {
        case .createAPIKey(let value),
            .renameAPIKey(
                _,
                let value
            ):
            name = value
        default: return
        }
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 16 else {
            throw NetworkError.server(
                code: 400,
                message: "API key names must contain 1–16 characters."
            )
        }
    }
}
