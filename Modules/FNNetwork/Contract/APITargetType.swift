//
//  APITargetType.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
@preconcurrency import Moya

/// Adds per-request authentication and validation to Moya's endpoint contract.
public protocol APITargetType: TargetType, Sendable {

    /// Whether the caller must supply a bearer credential.
    var requiresAuthorization: Bool { get }

    /// Validates user input before any transport operation is created.
    func validate() throws
}

extension APITargetType {

    /// The target-selected platform origin shared by account and API-key endpoints.
    public var baseURL: URL { NetworkEnvironment.current.baseURL }

    /// The common JSON headers, excluding credentials and application state.
    public var headers: [String: String]? { ["Accept": "application/json", "Content-Type": "application/json"] }

    /// An empty default fixture; tests inject their own transport responses.
    public var sampleData: Data { Data() }

    /// Most targets have no additional input restrictions.
    public func validate() throws {}
}

/// Applies an explicitly supplied environment and credential to one Moya target.
struct AuthorizedTarget<Value: APITargetType>: TargetType {

    /// The route and request parameters supplied by the API enumeration.
    let target: Value

    /// The client-scoped platform origin.
    let baseURL: URL

    /// The normalized credential retained only for this operation.
    let credential: String

    /// The unmodified service-relative route.
    var path: String { target.path }

    /// The endpoint's HTTP verb.
    var method: Moya.Method { target.method }

    /// The endpoint's JSON or query-parameter encoding.
    var task: Moya.Task { target.task }

    /// The endpoint's injected test fixture, if any.
    var sampleData: Data { target.sampleData }

    /// Adds bearer authorization without consulting business-module state.
    var headers: [String: String]? {
        var headers = target.headers ?? [:]
        if !credential.isEmpty { headers["Authorization"] = "Bearer \(credential)" }
        return headers
    }
}
