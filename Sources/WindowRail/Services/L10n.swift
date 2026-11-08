import Foundation

/// Both AppKit and SwiftUI use the same strings and the system's language order.
enum L10n {
    #if SWIFT_PACKAGE
    static let resources = Bundle.module
    #else
    static let resources = Bundle(path: Bundle.main.bundlePath + "/WindowRailResources.bundle") ?? Bundle.main
    #endif

    static func text(_ key: String, language: String? = nil, bundle: Bundle = resources) -> String {
        let preferences = language.map { [$0] } ?? Locale.preferredLanguages
        let selected = Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: preferences).first ?? "en"
        let path = bundle.path(forResource: selected, ofType: "lproj") ?? bundle.path(forResource: "en", ofType: "lproj")
        let localized = path.flatMap(Bundle.init(path:)) ?? bundle
        return localized.localizedString(forKey: key, value: nil, table: "Localizable")
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}
