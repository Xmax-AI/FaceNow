//
//  NetworkRepository.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Factory
import Foundation
@preconcurrency import Moya

/// Reports transport, envelope, and payload failures without logging credentials.
public enum NetworkError: Error, LocalizedError, Sendable {

    /// The endpoint cannot be represented as a secure service URL.
    case invalidURL

    /// An authenticated endpoint was called without a credential.
    case missingCredential

    /// The server returned an unexpected HTTP or JSON representation.
    case invalidResponse

    /// The HTTP or business response rejected the operation.
    case server(code: Int, message: String)

    /// A successful response omitted its required data.
    case missingData

    /// Whether the server explicitly rejected the caller's authentication.
    public var isUnauthorized: Bool {
        guard
            case .server(
                let code,
                _
            ) = self
        else { return false }
        return code == 401 || code == 46002
    }

    /// A user-facing description suitable for the account form.
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "The service address is invalid."
        case .missingCredential: return "Please sign in to continue."
        case .invalidResponse: return "The service returned an unexpected response. Please try again."
        case .server(
            let code,
            let message
        ):
            return message.isEmpty ? "Request failed (\(code)). Please try again." : message
        case .missingData: return "The service response is incomplete. Please try again."
        }
    }
}

/// Owns the Moya provider on one actor and maps platform envelopes through HandyJSON.
public actor NetworkRepository {

    /// The client-scoped origin; targets cannot redirect bearer credentials to another host.
    public nonisolated let baseURL: URL

    /// The provider is confined to this actor; Alamofire manages its connection pool.
    private let provider: MoyaProvider<MultiTarget>

    /// Creates an injectable Moya transport using an ephemeral Alamofire session by default.
    public init(
        baseURL: URL = URL(string: "https://cloud.xmax.22duck.cn")!,
        session: Moya.Session? = nil
    ) {
        self.baseURL = baseURL
        let session =
            session
            ?? Moya.Session(
                configuration: .ephemeral,
                startRequestsImmediately: false
            )
        provider = MoyaProvider<MultiTarget>(
            requestClosure: { endpoint, completion in
                do { completion(.success(try Self.makeRequest(endpoint))) } catch let error as MoyaError {
                    completion(.failure(error))
                } catch {
                    completion(
                        .failure(
                            .underlying(
                                error,
                                nil
                            )
                        )
                    )
                }
            },
            session: session
        )
    }

    /// Builds the same Moya request used by transport, without issuing network traffic.
    public nonisolated func request<Target: APITargetType>(
        for target: Target,
        bearerToken: String? = nil
    ) throws -> URLRequest {
        let configured = try authorized(
            target,
            bearerToken: bearerToken
        )
        let endpoint = MoyaProvider<AuthorizedTarget<Target>>.defaultEndpointMapping(for: configured)
        return try Self.makeRequest(endpoint)
    }

    /// Sends a target with cancellation propagated to Moya's underlying request.
    public func send<Target: APITargetType, Value: ResponseValue>(
        _ target: Target,
        as type: Value.Type,
        bearerToken: String? = nil
    ) async throws -> Value {
        try _Concurrency.Task.checkCancellation()
        let configured = try authorized(
            target,
            bearerToken: bearerToken
        )
        let cancellation = RequestCancellation()
        let response: HTTPResponse
        do {
            response = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let request = provider.request(MultiTarget(configured)) { result in
                        switch result {
                        case .success(let response):
                            continuation.resume(
                                returning: HTTPResponse(
                                    status: response.statusCode,
                                    data: response.data
                                )
                            )
                        case .failure(let error): continuation.resume(throwing: error)
                        }
                    }
                    cancellation.install(request)
                }
            } onCancel: {
                cancellation.cancel()
            }
        } catch {
            try _Concurrency.Task.checkCancellation()
            throw error
        }
        try _Concurrency.Task.checkCancellation()
        let object = (try? JSONSerialization.jsonObject(with: response.data)) as? [String: Any]
        let metadata = object.flatMap { ResponseMetadata.deserialize(from: $0) }
        guard (200..<300).contains(response.status) else {
            throw NetworkError.server(
                code: response.status,
                message: metadata?.message ?? ""
            )
        }
        guard let object, let metadata, let success = metadata.success, let code = metadata.code else {
            throw NetworkError.invalidResponse
        }
        guard success, code == 200 else {
            throw NetworkError.server(
                code: code,
                message: metadata.message ?? ""
            )
        }
        let value = object["data"] ?? NSNull()
        if value is NSNull, Value.self != EmptyResponse.self { throw NetworkError.missingData }
        guard let mapped = Value.mapJSON(value) else { throw NetworkError.invalidResponse }
        return mapped
    }

    /// Validates the route and scopes a credential to this single target.
    private nonisolated func authorized<Target: APITargetType>(
        _ target: Target,
        bearerToken: String?
    ) throws -> AuthorizedTarget<Target> {
        guard baseURL.scheme == "https", baseURL.host != nil,
            target.path.hasPrefix("/"), !target.path.contains("?")
        else { throw NetworkError.invalidURL }
        try target.validate()
        let credential = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !target.requiresAuthorization || !credential.isEmpty else { throw NetworkError.missingCredential }
        return AuthorizedTarget(
            target: target,
            baseURL: baseURL,
            credential: credential
        )
    }

    /// Applies the timeout and cache policy consistently to tests and live requests.
    private nonisolated static func makeRequest(
        _ endpoint: Endpoint
    ) throws -> URLRequest {
        var request = try endpoint.urlRequest()
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }
}

/// Copies only Sendable HTTP values out of Moya's completion callback.
private struct HTTPResponse: Sendable {

    /// The HTTP status returned by transport.
    let status: Int

    /// The unmodified response bytes, without request headers or credentials.
    let data: Data
}

/// Serializes cancellation before or after Moya returns its request handle.
///
/// Every mutable field is protected by the lock; cancellation is performed outside it.
private final class RequestCancellation: @unchecked Sendable {

    /// Protects both handle installation and the cancellation flag.
    private let lock = NSLock()

    /// The handle returned by Moya after request creation.
    private var request: (any Cancellable)?

    /// Remembers cancellation that arrives before the handle is available.
    private var isCancelled = false

    /// Installs the handle and immediately cancels it if cancellation already arrived.
    func install(
        _ request: any Cancellable
    ) {
        lock.lock()
        let shouldCancel = isCancelled
        if !shouldCancel { self.request = request }
        lock.unlock()
        if shouldCancel { request.cancel() }
    }

    /// Cancels at most once, including when called before handle installation.
    func cancel() {
        lock.lock()
        isCancelled = true
        let request = request
        self.request = nil
        lock.unlock()
        request?.cancel()
    }
}

public extension Container {

    /// The shared Network repository registered for this container.
    var networkRepo: Factory<NetworkRepository> {
        Factory(self) { NetworkRepository() }.singleton
    }
}
