//
//  NetworkEnvironment.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// Defines the regional platform origins shared by account, API-key, and credit requests.
public enum NetworkEnvironment: String, CaseIterable, Equatable, Sendable {

    /// The domestic platform used by XmaxCamera.
    case china

    /// The overseas platform used by FaceNow-oversea.
    case global

    /// Selects the platform at the application compilation boundary.
    public static let current: NetworkEnvironment = {
        #if OVERSEA
            return .global
        #else
            return .china
        #endif
    }()

    /// The origin without service prefixes, matching api-platform-web's regional defaults.
    public var baseURL: URL {
        switch self {
        case .china: URL(string: "https://cloud.xmax.22duck.cn")!
        case .global: URL(string: "https://api.xmax.cloud")!
        }
    }

    /// The public website opened by the regional application.
    public var websiteURL: URL {
        switch self {
        case .china: URL(string: "https://xmaxai.com")!
        case .global: URL(string: "https://xmax.ai")!
        }
    }

    /// The browser-based account platform, independent of the API service origin.
    public var platformURL: URL {
        switch self {
        case .china: URL(string: "https://platform.xmaxai.com")!
        case .global: URL(string: "https://platform.xmax.ai")!
        }
    }

    /// The regional terms shared by login, onboarding, and the account menu.
    public var termsURL: URL { platformURL.appendingPathComponent("docs/resources/terms") }

    /// The regional privacy policy shared by all application entry points.
    public var privacyURL: URL { platformURL.appendingPathComponent("docs/resources/privacy") }

    /// The troubleshooting guide, retaining each region's configured URL scheme.
    public var troubleshootingURL: URL {
        switch self {
        case .china: websiteURL.appendingPathComponent("facenow/guide")
        case .global: URL(string: "http://xmax.ai/facenow/guide")!
        }
    }
}
