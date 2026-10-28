//
//  UserLoginDraft.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// Retains editable values for one verification channel while the user switches channels.
struct UserLoginDraft {

    /// The untrimmed destination shown in the native editor.
    var account = ""

    /// The entered verification code, invalidated when its destination changes.
    var code = ""
}
