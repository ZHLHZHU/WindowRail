import AppKit
import SwiftUI
import ServiceManagement

final class PreferencesModel: ObservableObject {
    @Published private(set) var showMenuBarIcon: Bool
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    @Published var errorMessage: String?
    var onMenuBarVisibilityChanged: ((Bool) -> Void)?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
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
            errorMessage = L10n.format("login.error", error.localizedDescription)
        }
        refreshLoginStatus()
    }
}
