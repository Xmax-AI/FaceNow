//
//  Localization.swift
//  FaceNow
//

import Foundation

/// Resolves app-owned text with an explicit language, independent of the system's preferences.
public enum Localization {

    /// The app target fixes its language independently of system and user preferences.
    #if OVERSEA
        public static let languageCode = "en"
    #else
        public static let languageCode = "zh-Hans"
    #endif

    /// The locale used when formatting parameters inside app-owned localized messages.
    public static let locale = Locale(identifier: languageCode)

    /// Reads the selected language's table, falling back to the English source text for missing resources.
    public static func string(
        _ key: String,
        table: String = "Localizable",
        defaultValue: String,
        bundle: Bundle = .main
    ) -> String {
        guard let url = bundle.url(forResource: languageCode, withExtension: "lproj"),
            let languageBundle = Bundle(url: url)
        else { return defaultValue }
        return languageBundle.localizedString(forKey: key, value: defaultValue, table: table)
    }

    /// Formats a complete localized sentence, preserving positional placeholders and the fixed app locale.
    public static func format(
        _ key: String,
        table: String = "Localizable",
        defaultValue: String,
        arguments: [CVarArg],
        bundle: Bundle = .main
    ) -> String {
        String(
            format: string(key, table: table, defaultValue: defaultValue, bundle: bundle),
            locale: locale,
            arguments: arguments
        )
    }
}
