import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    static let windowSize = NSSize(width: 460, height: 250)
    var version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L10n.text("app.development")
    @ObservedObject var preferences: PreferencesModel
    let openPermissions: () -> Void
    let quit: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle(L10n.text("login.toggle"), isOn: Binding(get: { preferences.launchAtLogin }, set: preferences.setLaunchAtLogin))
                    if preferences.loginStatus == .requiresApproval {
                        HStack {
                            Text(L10n.text("login.approval"))
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(L10n.text("systemSettings.open")) { SMAppService.openSystemSettingsLoginItems() }
                        }
                    }
                }
                Section {
                    Toggle(L10n.text("menuBar.toggle"), isOn: Binding(get: { preferences.showMenuBarIcon }, set: preferences.setMenuBarIcon))
                    Text(L10n.text("menuBar.help"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let message = preferences.errorMessage {
                    Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }.formStyle(.grouped)
            HStack {
                Button(L10n.text("accessibility.open"), action: openPermissions)
                Spacer()
                Button(L10n.text("app.quit"), action: quit)
            }
            .controlSize(.small)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            Divider()
            HStack(spacing: 6) {
                Text("WindowRail")
                Text(version)
                    .accessibilityLabel(L10n.format("app.version", version))
                Text("·")
                Link("GitHub", destination: URL(string: "https://github.com/ZHLHZHU/WindowRail")!)
                    .foregroundStyle(Color(nsColor: .linkColor))
                    .help(L10n.text("app.githubHelp"))
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
