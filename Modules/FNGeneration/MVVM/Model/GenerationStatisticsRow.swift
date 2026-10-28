//
//  GenerationStatisticsRow.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// A formatted metric value and optional explanation for one statistics row.
struct GenerationStatisticsRow: Identifiable {

    /// The identity used to associate this value with its displayed or pending state.
    let id: String

    /// The localized display label, independent of the stable metric identity.
    var title: String { GenerationStrings.statisticsTitle(id) }

    /// The formatted metric value, using a dash when the source value is unavailable.
    var value = "—"

    /// The metric definition or availability explanation displayed as a tooltip.
    var help = ""

    /// Whether the row is separated and emphasized as a total measurement.
    var total = false
}
