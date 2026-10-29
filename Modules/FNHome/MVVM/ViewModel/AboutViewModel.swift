//
//  AboutViewModel.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// Supplies static product content without fetching data or changing an account or camera session.
@MainActor
final class AboutViewModel {

    /// One advantage card, separating copy and symbol identity from native layout.
    struct Advantage {
        let symbol: String
        let title: String
        let metric: String
        let detail: String
    }

    /// Reflects the three product advantages supplied for the About Us section.
    var advantages: [Advantage] {
        [
            Advantage(
                symbol: "bolt.fill",
                title: HomeStrings.aboutLatencyTitle,
                metric: HomeStrings.aboutLatencyMetric,
                detail: HomeStrings.aboutLatencyDetail
            ),
            Advantage(
                symbol: "dollarsign.circle.fill",
                title: HomeStrings.aboutCostTitle,
                metric: HomeStrings.aboutCostMetric,
                detail: HomeStrings.aboutCostDetail
            ),
            Advantage(
                symbol: "sparkles",
                title: HomeStrings.aboutFidelityTitle,
                metric: HomeStrings.aboutFidelityMetric,
                detail: HomeStrings.aboutFidelityDetail
            ),
        ]
    }
}
