//
//  ResponseModel.swift
//  FaceNow
//

import Foundation
import HandyJSON

/// Maps the envelope's data value to an explicitly requested response type.
public protocol ResponseValue: Sendable {

    /// Validates and maps a JSON value without silently discarding malformed records.
    static func mapJSON(
        _ value: Any
    ) -> Self?
}

/// Uses HandyJSON for DTO mapping after endpoint-specific shape validation.
public protocol ResponseModel: HandyJSON, ResponseValue {

    /// Checks required response fields before HandyJSON applies default values.
    static func isValidJSON(
        _ value: [String: Any]
    ) -> Bool
}

extension ResponseModel {

    /// Maps a JSON object through HandyJSON only after its required fields are present.
    public static func mapJSON(
        _ value: Any
    ) -> Self? {
        guard let object = value as? [String: Any], isValidJSON(object) else { return nil }
        return Self.deserialize(from: object)
    }
}

extension String: ResponseValue {

    /// Reads the token string returned directly by the domestic login endpoint.
    public static func mapJSON(
        _ value: Any
    ) -> String? { value as? String }
}

extension Array: ResponseValue where Element: ResponseValue {

    /// Rejects a malformed list element instead of silently shortening the response.
    public static func mapJSON(
        _ value: Any
    ) -> [Element]? {
        guard let values = value as? [Any] else { return nil }
        var result: [Element] = []
        for value in values {
            guard let item = Element.mapJSON(value) else { return nil }
            result.append(item)
        }
        return result
    }
}

/// Represents an acknowledged operation whose data may be null or an object.
public struct EmptyResponse: ResponseValue {

    /// Creates the empty acknowledgement value.
    public init() {}

    /// Accepts the shapes used by code-send, logout, and key-deletion responses.
    public static func mapJSON(
        _ value: Any
    ) -> EmptyResponse? {
        value is NSNull || value is [String: Any] ? EmptyResponse() : nil
    }
}

/// Maps business status independently of the endpoint's payload type.
struct ResponseMetadata: HandyJSON {

    /// The service's explicit success flag.
    var success: Bool?

    /// The business status, independent of HTTP status.
    var code: Int?

    /// The service-provided explanation, when present.
    var message: String?
}
