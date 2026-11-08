import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    static let windowSize = NSSize(width: 460, height: 300)
    var version: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    @ObservedObject var preferences: PreferencesModel
    let openPermissions: () -> Void
    let quit: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker(L10n.text(.languageTitle), selection: Binding(get: { preferences.language }, set: preferences.setLanguage)) {
                        Text(L10n.text(.languageSystem)).tag("")
                        ForEach(L10n.availableLanguages, id: \.self) { identifier in
                            Text(L10n.languageName(identifier)).tag(identifier)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section {
                    Toggle(L10n.text(.loginToggle), isOn: Binding(get: { preferences.launchAtLogin }, set: preferences.setLaunchAtLogin))
                    if preferences.loginStatus == .requiresApproval {
                        HStack {
                            Text(L10n.text(.loginApproval))
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(L10n.text(.systemSettingsOpen)) { SMAppService.openSystemSettingsLoginItems() }
                        }
                    }
                }
                Section {
                    Toggle(L10n.text(.menuBarToggle), isOn: Binding(get: { preferences.showMenuBarIcon }, set: preferences.setMenuBarIcon))
                    Text(L10n.text(.menuBarHelp))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    HStack {
                        Button(L10n.text(.accessibilityOpen), action: openPermissions)
                        Spacer()
                        Button(L10n.text(.appQuit), action: quit)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .padding(.vertical, 2)
                }
                if let message = preferences.errorMessage {
                    Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }.formStyle(.grouped)
            Divider()
            HStack(spacing: 6) {
                Text("WindowRail")
                Text(version ?? L10n.text(.appDevelopment))
                    .accessibilityLabel(L10n.format(.appVersion, version ?? L10n.text(.appDevelopment)))
                Text("·")
                Link("GitHub", destination: URL(string: "https://github.com/ZHLHZHU/WindowRail")!)
                    .foregroundStyle(Color(nsColor: .linkColor))
                    .help(L10n.text(.appGithubHelp))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .onAppear { preferences.refreshLoginStatus() }
    }
}
