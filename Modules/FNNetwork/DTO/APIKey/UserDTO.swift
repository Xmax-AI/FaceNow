//
//  UserDTO.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
import HandyJSON

/// The documented active API key record owned by the current platform user.
public struct APIKeyRecord: ResponseModel, Identifiable {

    /// The record identifier used for rename and deletion.
    public var uid = ""

    /// The owning account tenant.
    public var tenantName = ""

    /// The owning user's identifier.
    public var userUid = ""

    /// The user-visible key name.
    public var name = ""

    /// The plaintext credential returned by the platform; never include it in logs.
    public var apiKey = ""

    /// The record state, normally active for list results.
    public var status = ""

    /// The optional server creation timestamp, retained without locale conversion.
    public var createTimestamp: String? = nil

    /// The optional server modification timestamp.
    public var updateTimestamp: String? = nil

    /// The stable identity used by account views.
    public var id: String { uid }

    /// Creates an empty DTO for HandyJSON's field mapping.
    public init() {}

    /// Rejects incomplete key records instead of treating defaults as server data.
    public static func isValidJSON(
        _ value: [String: Any]
    ) -> Bool {
        ["uid", "tenantName", "userUid", "name", "apiKey", "status"].allSatisfy { value[$0] is String }
    }
}

/// Encodes the only mutable fields allowed by API-key creation and rename.
struct APIKeyRequest: HandyJSON {

    /// The existing key identifier, omitted when creating a key.
    var uid: String?

    /// The validated key display name.
    var name = ""
}
