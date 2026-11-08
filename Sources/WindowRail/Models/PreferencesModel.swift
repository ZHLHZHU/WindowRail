import AppKit
import SwiftUI
import ServiceManagement

final class PreferencesModel: ObservableObject {
    @Published private(set) var language: String
    @Published private(set) var showMenuBarIcon: Bool
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    @Published var errorMessage: String?
    var onLanguageChanged: ((String) -> Void)?
    var onMenuBarVisibilityChanged: ((Bool) -> Void)?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = L10n.validChoice(defaults.string(forKey: "appLanguage") ?? "")
        showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
    }
    func setLanguage(_ identifier: String) {
        let choice = L10n.validChoice(identifier)
        guard language != choice else { return }
        defaults.set(choice, forKey: "appLanguage")
        // AppKit and background lookups update before SwiftUI renders this change.
        onLanguageChanged?(choice)
        language = choice
        errorMessage = nil
    }
    var launchAtLogin: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }
    func refreshLoginStatus() { loginStatus = SMAppService.mainApp.status }
    func setMenuBarIcon(_ visible: Bool) {
        defaults.set(visible, forKey: "showMenuBarIcon")
        showMenuBarIcon = visible
        onMenuBarVisibilityChanged?(visible)
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        errorMessage = nil
        refreshLoginStatus()
        if enabled == launchAtLogin { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = L10n.format(.loginError, error.localizedDescription)
        }
        refreshLoginStatus()
    }
}
