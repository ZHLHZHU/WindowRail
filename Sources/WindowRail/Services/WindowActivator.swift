import AppKit
import ApplicationServices
import OSLog

/// Application activation is asynchronous. App-only rows also need the reopen
/// action (like clicking the Dock), which activate(options:) alone never sends.
final class WindowActivator {
    private var generation = 0
    private let log = Logger(subsystem: "local.windowrail.app", category: "activation")

    func activate(_ entry: WindowEntry) {
        generation += 1
        let token = generation
        guard !entry.app.isTerminated else { return }
        entry.app.unhide()
        guard let window = entry.window else {
            reopen(entry.app, token: token)
            return
        }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        let accepted = entry.app.activate(options: [])
        log.debug("Window activation request pid=\(entry.pid) accepted=\(accepted)")
        raise(window, app: entry.app)
        // Let the target finish activation / unminimizing before raising again.
        for delay in [0.10, 0.30] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.generation == token, !entry.app.isTerminated else { return }
                self.raise(window, app: entry.app)
            }
        }
        if !accepted { reopen(entry.app, token: token, window: window) }
    }
    private func raise(_ window: AXUIElement, app: NSRunningApplication) {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)
        AXUIElementSetAttributeValue(root, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        let result = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        log.debug("Window raise pid=\(app.processIdentifier) result=\(result.rawValue)")
    }
    private func reopen(_ app: NSRunningApplication, token: Int, window: AXUIElement? = nil) {
        guard let url = app.bundleURL else {
            app.activate(options: [.activateAllWindows])
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] opened, error in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                if let error {
                    self.log.error("Application reopen failed: \(error.localizedDescription, privacy: .public)")
                    let alert = NSAlert()
                    alert.messageText = L10n.text("app.openError")
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                    return
                }
                if let opened {
                    opened.unhide()
                    opened.activate(options: [])
                    if let window { self.raise(window, app: opened) }
                }
            }
        }
    }
}
