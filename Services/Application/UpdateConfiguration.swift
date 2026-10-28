//
//  UpdateConfiguration.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// Requires a real HTTPS feed and an Ed25519 public key before starting automatic updates.
struct UpdateConfiguration: Equatable, Sendable {

    /// The server-owned appcast URL embedded at build time.
    let feedURL: URL

    /// The base64-encoded public key authenticating update archives.
    let publicKey: String

    /// Rejects missing, partially configured, or unresolved build settings.
    init?(
        infoDictionary: [String: Any]
    ) {
        guard let feed = infoDictionary["SUFeedURL"] as? String,
            let key = infoDictionary["SUPublicEDKey"] as? String,
            !feed.contains("$("), !key.contains("$("),
            let components = URLComponents(string: feed),
            components.scheme == "https", let host = components.host, !host.isEmpty,
            components.user == nil, components.password == nil, components.fragment == nil,
            let url = components.url,
            let keyData = Data(base64Encoded: key), keyData.count == 32
        else { return nil }
        feedURL = url
        publicKey = key
    }
}
