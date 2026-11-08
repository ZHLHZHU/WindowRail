import SwiftUI
import ServiceManagement

struct PreferencesView: View {
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
            Divider()
            HStack {
                Button(L10n.text("accessibility.open"), action: openPermissions)
                Spacer()
                Button(L10n.text("app.quit"), action: quit)
            }.padding(16)
        }
        .frame(width: 460, height: 290)
        .onAppear { preferences.refreshLoginStatus() }
    }
}
