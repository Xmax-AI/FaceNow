//
//  GenerationStatisticsGroup.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// Displays formatted metric values without rebuilding the video or reference views.
struct GenerationStatisticsGroup: Identifiable {

    /// The identity used to associate this value with its displayed or pending state.
    let id: String

    /// The metric rows displayed together in this statistics group.
    var rows: [GenerationStatisticsRow]
}
