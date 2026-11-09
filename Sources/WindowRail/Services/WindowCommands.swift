import AppKit
import ApplicationServices
import OSLog

enum WindowCommand: Int {
    case close, quit, minimize

    var titleKey: L10n.Key {
        switch self {
        case .close: return .windowClose
        case .quit: return .windowQuitApp
        case .minimize: return .windowMinimize
        }
    }

    static func availableItems(for entry: WindowEntry) -> [Self] {
        entry.window == nil ? [.quit] : [.close, .quit, .minimize]
    }

    func isEnabled(for entry: WindowEntry) -> Bool {
        guard !entry.app.isTerminated else { return false }
        if self == .quit { return true }
        guard AXIsProcessTrusted(), let window = entry.window else { return false }
        AXUIElementSetMessagingTimeout(window, 0.15)
        switch self {
        case .close:
            guard let button = closeButton(for: window) else { return false }
            return (attribute(button, kAXEnabledAttribute) as? Bool) != false
        case .minimize:
            var settable = DarwinBoolean(false)
            return AXUIElementIsAttributeSettable(window, kAXMinimizedAttribute as CFString, &settable) == .success
                && settable.boolValue && (attribute(window, kAXMinimizedAttribute) as? Bool) != true
        case .quit: return true
        }
    }

    func perform(on entry: WindowEntry) {
        guard !entry.app.isTerminated else { return }
        if self == .quit {
            if !entry.app.terminate() { NSSound.beep() }
            return
        }
        guard AXIsProcessTrusted(), let window = entry.window else { return }
        AXUIElementSetMessagingTimeout(window, 0.15)
        let result: AXError
        switch self {
        case .close:
            guard let button = closeButton(for: window) else { NSSound.beep(); return }
            result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        case .minimize:
            result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        case .quit: return
        }
        if result != .success {
            Logger(subsystem: "local.windowrail.app", category: "windowCommands")
                .debug("Window action failed with AX error \(result.rawValue)")
            NSSound.beep()
        }
    }

    private func closeButton(for window: AXUIElement) -> AXUIElement? {
        guard let value = attribute(window, kAXCloseButtonAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let button = value as! AXUIElement
        AXUIElementSetMessagingTimeout(button, 0.15)
        return button
    }
}
