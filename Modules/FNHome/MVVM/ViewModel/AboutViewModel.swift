//
//  AboutViewModel.swift
//  FaceNow
//

import Foundation

/// Supplies static product content without fetching data or changing an account or camera session.
@MainActor
final class AboutViewModel {

    /// One advantage card, separating copy and symbol identity from native layout.
    struct Advantage {

        /// The system symbol representing the advantage.
        let symbol: String

        /// The localized card heading.
        let title: String

        /// The short value emphasized on the card.
        let metric: String

        /// The localized explanation beneath the value.
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
