import AppKit
import ApplicationServices
import OSLog

/// Application activation is asynchronous. App-only rows also need the reopen
/// action (like clicking the Dock), which activate(options:) alone never sends.
final class WindowActivator {
    private let queue = DispatchQueue(label: "local.windowrail.activate", qos: .userInitiated)
    private let generationLock = NSLock()
    private var generation = 0
    private let log = Logger(subsystem: "local.windowrail.app", category: "activation")

    private func isCurrent(_ token: Int) -> Bool {
        generationLock.lock()
        defer { generationLock.unlock() }
        return generation == token
    }

    func activate(_ entry: WindowEntry) {
        generationLock.lock()
        generation += 1
        let token = generation
        generationLock.unlock()

        // AX messages can wait on another application. Keep them off the event tap's run loop.
        let enqueuedAt = DispatchTime.now()
        SwitchTiming.record("Activation \(token) queued")
        queue.async { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            SwitchTiming.record("Activation \(token) started after \(SwitchTiming.milliseconds(since: enqueuedAt.uptimeNanoseconds)) ms in queue")
            self.reportSlow("queue", since: enqueuedAt, token: token)
            self.activate(entry, token: token)
        }
    }

    private func activate(_ entry: WindowEntry, token: Int) {
        guard isCurrent(token), !entry.app.isTerminated else { return }
        let started = DispatchTime.now()
        defer { reportSlow("initial activation", since: started, token: token) }
        if entry.app.isHidden { entry.app.unhide() }
        guard let window = entry.window else {
            requestReopen(entry.app, token: token)
            return
        }
        AXUIElementSetMessagingTimeout(window, 0.08)
        let wasMinimized = (attribute(window, kAXMinimizedAttribute) as? Bool) == true
        guard isCurrent(token) else { return }
        if wasMinimized {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        guard isCurrent(token) else { return }
        let alreadyActive = entry.app.isActive
        let accepted = alreadyActive || entry.app.activate(options: [])
        SwitchTiming.record("Activation \(token) app activation accepted: \(accepted), already active: \(alreadyActive)")
        log.debug("Window activation request pid=\(entry.pid) accepted=\(accepted)")
        if alreadyActive && !wasMinimized {
            // A visible window in the active app can usually be raised directly.
            // If focus does not follow, the retry uses AXMain and AXRaise.
            performRaise(window, token: token)
        } else {
            raise(window, app: entry.app, token: token)
        }
        for delay in [0.10, 0.30] {
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.raise(window, app: entry.app, token: token, checkFocus: true)
            }
        }
        if !accepted { requestReopen(entry.app, token: token, window: window) }
    }

    private func raise(_ window: AXUIElement, app: NSRunningApplication, token: Int, checkFocus: Bool = false) {
        guard isCurrent(token), !app.isTerminated else { return }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.08)
        if checkFocus, app.isActive, let focused = attribute(root, kAXFocusedWindowAttribute),
           CFEqual(focused, window) { return }
        guard isCurrent(token) else { return }
        if !app.isActive {
            AXUIElementSetAttributeValue(root, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        guard isCurrent(token) else { return }
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        performRaise(window, token: token)
    }

    private func performRaise(_ window: AXUIElement, token: Int) {
        guard isCurrent(token) else { return }
        let started = DispatchTime.now()
        let result = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        SwitchTiming.record("Activation \(token) AXRaise result \(result.rawValue) after \(SwitchTiming.milliseconds(since: started.uptimeNanoseconds)) ms")
        reportSlow("AXRaise", since: started, token: token)
        if result != .success && isCurrent(token) {
            log.notice("Window switch \(token) AXRaise returned \(result.rawValue)")
        }
    }

    private func reportSlow(_ phase: String, since start: DispatchTime, token: Int) {
        let milliseconds = (DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        if milliseconds >= 100 {
            log.notice("Window switch \(token) \(phase, privacy: .public) took \(milliseconds) ms")
        }
    }

    private func requestReopen(_ app: NSRunningApplication, token: Int, window: AXUIElement? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(token), !app.isTerminated else { return }
            self.reopen(app, token: token, window: window)
        }
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
                guard let self, self.isCurrent(token) else { return }
                if let error {
                    self.log.error("Application reopen failed: \(error.localizedDescription, privacy: .public)")
                    let alert = NSAlert()
                    alert.messageText = L10n.text(.appOpenError)
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                    return
                }
                if let opened {
                    opened.unhide()
                    opened.activate(options: [])
                    if let window {
                        self.queue.async { [weak self] in
                            self?.raise(window, app: opened, token: token)
                        }
                    }
                }
            }
        }
    }
}
