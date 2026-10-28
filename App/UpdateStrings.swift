//
//  UpdateStrings.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// Provides typed English text for the application update menu and explicit update actions.
enum UpdateStrings {

    /// The manual update-check menu item.
    static var checkForUpdates: String {
        Localization.string(
            "updates.check",
            table: "Common",
            defaultValue: "Check for Updates…"
        )
    }

    /// The title shown when this build has no configured update service.
    static var unavailable: String {
        Localization.string(
            "updates.unavailable.title",
            table: "Common",
            defaultValue: "Updates are not available yet"
        )
    }

    /// Explains an unavailable update service without exposing release settings.
    static var unavailableDetails: String {
        Localization.string(
            "updates.unavailable.details",
            table: "Common",
            defaultValue: "Automatic updates have not been enabled for this version of FaceNow."
        )
    }

    /// The title shown after the user requests installation during an active camera session.
    static var waiting: String {
        Localization.string(
            "updates.waiting.title",
            table: "Common",
            defaultValue: "Update ready to install"
        )
    }

    /// Explains how a postponed installation resumes.
    static var waitingDetails: String {
        Localization.string(
            "updates.waiting.details",
            table: "Common",
            defaultValue:
                "Stop camera preview or generation to finish installing the update. "
                + "FaceNow will then restart automatically."
        )
    }

    /// Dismisses an informational update alert.
    static var acknowledge: String {
        Localization.string(
            "updates.acknowledge",
            table: "Common",
            defaultValue: "OK"
        )
    }
}
