import Foundation

/// Shared by AppKit, SwiftUI and background window scans.
enum L10n {
    enum Key: String, CaseIterable {
        case settingsTitle = "settings.title"
        case settingsOpen = "settings.open"
        case sidebarToggle = "sidebar.toggle"
        case accessibilityOpen = "accessibility.open"
        case accessibilityEnable = "accessibility.enable"
        case keyboardRetry = "keyboard.retry"
        case appQuit = "app.quit"
        case loginToggle = "login.toggle"
        case loginApproval = "login.approval"
        case systemSettingsOpen = "systemSettings.open"
        case menuBarToggle = "menuBar.toggle"
        case menuBarHelp = "menuBar.help"
        case loginError = "login.error"
        case appOpenError = "app.openError"
        case windowCurrent = "window.current"
        case windowCurrentAccessibility = "window.currentAccessibility"
        case switcherTitle = "switcher.title"
        case switcherHelp = "switcher.help"
        case windowFallback = "window.fallback"
        case appFallback = "app.fallback"
        case groupApps = "group.apps"
        case groupFullscreen = "group.fullscreen"
        case groupDesktop = "group.desktop"
        case groupOther = "group.other"
        case appVersion = "app.version"
        case appDevelopment = "app.development"
        case appGithubHelp = "app.githubHelp"
        case languageTitle = "language.title"
        case languageSystem = "language.system"
    }

    #if SWIFT_PACKAGE
    static let resources = Bundle.module
    #else
    static let resources = Bundle(path: Bundle.main.bundlePath + "/WindowRailResources.bundle") ?? Bundle.main
    #endif

    /// Language identifiers come from bundled resources; an empty choice follows macOS.
    static var availableLanguages: [String] {
        languages(in: resources)
    }
    static func languages(in bundle: Bundle) -> [String] {
        // Foundation may report a language once from Info.plist and again from .lproj.
        Array(Set(bundle.localizations.filter { $0 != "Base" })).sorted()
    }
    static func validChoice(_ identifier: String) -> String {
        availableLanguages.contains(identifier) ? identifier : ""
    }
    private static let lock = NSLock()
    private static var override = validChoice(UserDefaults.standard.string(forKey: "appLanguage") ?? "")
    static var languageChoice: String {
        lock.lock()
        defer { lock.unlock() }
        return override
    }
    static func setLanguage(_ identifier: String) {
        let choice = validChoice(identifier)
        lock.lock()
        override = choice
        lock.unlock()
    }
    static func languageIdentifier(for choice: String) -> String {
        let preferences = choice.isEmpty ? Locale.preferredLanguages : [choice]
        return Bundle.preferredLocalizations(from: availableLanguages, forPreferences: preferences).first ?? "en"
    }
    static func languageName(_ identifier: String) -> String {
        Locale(identifier: identifier).localizedString(forIdentifier: identifier) ?? identifier
    }
    static var currentLanguage: String { languageIdentifier(for: languageChoice) }

    static func text(_ key: Key, language: String? = nil, bundle: Bundle = resources) -> String {
        let selected = languageIdentifier(for: language ?? languageChoice)
        let missing = "__WINDOWRAIL_MISSING_TRANSLATION__"
        func lookup(_ identifier: String) -> String? {
            guard let path = bundle.path(forResource: identifier, ofType: "lproj"),
                  let localized = Bundle(path: path) else { return nil }
            let value = localized.localizedString(forKey: key.rawValue, value: missing, table: "Localizable")
            return value == missing ? nil : value
        }
        // Fall back per key, even when a partially translated language bundle exists.
        return lookup(selected) ?? lookup("en") ?? key.rawValue
    }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: currentLanguage), arguments: arguments)
    }
}
