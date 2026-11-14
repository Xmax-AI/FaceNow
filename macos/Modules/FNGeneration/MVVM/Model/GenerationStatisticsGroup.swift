//
//  GenerationStatisticsGroup.swift
//  FaceNow
//

import Foundation

/// Displays formatted metric values without rebuilding the video or reference views.
struct GenerationStatisticsGroup: Identifiable {

    /// The identity used to associate this value with its displayed or pending state.
    let id: String

    /// The localized display label, independent of the stable metric identity.
    var title: String { GenerationStrings.statisticsTitle(id) }

    /// The metric rows displayed together in this statistics group.
    var rows: [GenerationStatisticsRow]
}
