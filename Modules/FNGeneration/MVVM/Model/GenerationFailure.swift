//
//  GenerationFailure.swift
//  FaceNow
//

import Foundation

/// Recognizes platform credit failures without changing unrelated server messages.
enum GenerationFailure {

    /// Prefers platform business codes and accepts explicit legacy credit-exhaustion descriptions.
    static func isInsufficientCredits(
        apiCode: Int?,
        message: String
    ) -> Bool {
        if apiCode == 43001 || apiCode == 46017 { return true }
        let detail = message.lowercased().replacingOccurrences(of: "_", with: " ")
        if ["积分不足", "余额不足", "积分已用完", "积分已耗尽", "余额已耗尽"].contains(where: detail.contains) {
            return true
        }
        return detail.range(
            of:
                #"\b(insufficient (credits?|points?|balance|funds)|not enough (credits?|points?)|out of (credits?|points?)|no credits?( remaining)?|(credits?|points?|balance|funds) (is |are )?(insufficient|exhausted|depleted)|credits? (have |has )?(run out|been exhausted|been depleted))\b"#,
            options: .regularExpression
        ) != nil
    }
}
