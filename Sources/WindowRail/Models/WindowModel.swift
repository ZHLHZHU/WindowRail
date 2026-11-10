import AppKit
import SwiftUI
import ApplicationServices

final class WindowModel: ObservableObject {
    @Published var entries: [WindowEntry] = []
    @Published var groups: [SidebarGroup] = []
    let spaceCatalog = SpaceCatalog()
    let activator = WindowActivator()
    var onActivate: (() -> Void)?
    @Published var trusted = AXIsProcessTrusted()
    @Published var keyboardReady = false
    @Published var selecting = false
    @Published var choices: [WindowEntry] = []
    @Published var selection = 0
    @Published var originWindowID: String?
    var recent: [String] = []
    var previousMembership: [String: [UInt64]] = [:]
    private let scanQueue = DispatchQueue(label: "local.windowrail.scan", qos: .userInitiated)
    private var refreshInProgress = false
    var lastFocused: String?
    private var activationRevision = 0
    var onSelectionChange: (() -> Void)?
    var onEndSelection: (() -> Void)?

    func refresh() {
        trusted = AXIsProcessTrusted()
        guard !selecting, !refreshInProgress else { return }
        refreshInProgress = true
        let trusted = self.trusted
        let savedMembership = previousMembership
        let scanRevision = activationRevision
        scanQueue.async { [self] in
            var scanMembership = savedMembership
            spaceCatalog.refresh()
            var result: [WindowEntry] = []
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            var focusedID: String?
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != getpid() {
                let root = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(root, 0.12)
                let windows = trusted ? (attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []) : []
                let focused = trusted ? attribute(root, kAXFocusedWindowAttribute) : nil
                var count = 0
                for window in windows {
                    let subrole = attribute(window, kAXSubroleAttribute) as? String
                    guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }
                    let title = (attribute(window, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 } ?? app.localizedName ?? L10n.text(.windowFallback)
                    let windowID = spaceCatalog.id(for: window)
                    let id = "\(app.processIdentifier):\(windowID.map(String.init) ?? String(CFHash(window)))"
                    let membership = spaceCatalog.memberships(for: windowID)
                    if !membership.isEmpty { scanMembership[id] = membership }
                    result.append(WindowEntry(id: id, pid: app.processIdentifier, app: app, window: window, title: title, fullScreen: (attribute(window, "AXFullScreen") as? Bool) == true, spaceIDs: membership.isEmpty ? scanMembership[id] ?? [] : membership))
                    count += 1
                    if app.processIdentifier == frontPID, let focused, CFEqual(focused, window) { focusedID = id }
                }
                if count == 0 {
                    let id = "app:\(app.processIdentifier)"
                    result.append(WindowEntry(id: id, pid: app.processIdentifier, app: app, window: nil, title: app.localizedName ?? L10n.text(.appFallback)))
                    if app.processIdentifier == frontPID { focusedID = id }
                }
            }
            let scannedEntries = result
            let scannedFocus = focusedID
            let scannedMembership = scanMembership
            DispatchQueue.main.async { [self] in
                defer { refreshInProgress = false }
                guard !selecting else { return }
                let result = scannedEntries
                let focusedID = scannedFocus
                previousMembership = scannedMembership
                if scanRevision == activationRevision, let focusedID, focusedID != lastFocused {
                    recent.removeAll { $0 == focusedID }
                    recent.insert(focusedID, at: 0)
                    lastFocused = focusedID
                }
                let ids = Set(result.map(\.id))
                recent.removeAll { !ids.contains($0) }
                previousMembership = previousMembership.filter { ids.contains($0.key) }
                let rank = Dictionary(uniqueKeysWithValues: recent.enumerated().map { ($0.element, $0.offset) })
                entries = result.sorted {
                    let a = rank[$0.id] ?? Int.max, b = rank[$1.id] ?? Int.max
                    if a != b { return a < b }
                    let appA = $0.app.localizedName ?? "", appB = $1.app.localizedName ?? ""
                    return appA == appB ? $0.title < $1.title : appA < appB
                }
                groups = spaceCatalog.groups(for: entries)
            }
        }
    }
    func refreshLocalizedGroups() {
        var desktop = 0
        groups = groups.map { group in
            let title: String
            switch group.id {
            case "apps": title = L10n.text(.groupApps)
            case "fullscreen": title = L10n.text(.groupFullscreen)
            case "unknown": title = L10n.text(.groupOther)
            default:
                if group.id.hasPrefix("space:") {
                    desktop += 1
                    title = L10n.format(.groupDesktop, desktop)
                } else { title = group.title }
            }
            return SidebarGroup(id: group.id, title: title, entries: group.entries)
        }
    }
    func step(sameApp: Bool, backwards: Bool) {
        guard trusted else { return }
        if selecting {
            moveSelection(backwards: backwards)
            return
        }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        beginSelection(sameApp: sameApp, frontPID: frontPID,
                       focusedID: focusedWindowID(for: frontPID), backwards: backwards)
    }

    func beginSelection(sameApp: Bool, frontPID: pid_t?, focusedID: String?, backwards: Bool) {
        let candidates = entries.filter { !sameApp || $0.pid == frontPID }
        guard !candidates.isEmpty else { return }

        if sameApp {
            // Keep the cycle order stable as each window becomes the most recent.
            choices = candidates.sorted { $0.id < $1.id }
        } else {
            let rank = Dictionary(uniqueKeysWithValues: recent.enumerated().map { ($0.element, $0.offset) })
            choices = candidates.enumerated().sorted { first, second in
                let a = rank[first.element.id] ?? Int.max
                let b = rank[second.element.id] ?? Int.max
                return a == b ? first.offset < second.offset : a < b
            }.map(\.element)
        }

        let frontChoices = choices.filter { $0.pid == frontPID }
        let currentID = focusedID
            ?? recent.first { id in frontChoices.contains { $0.id == id } }
            ?? frontChoices.first?.id
        originWindowID = sameApp ? currentID : nil
        if let index = choices.firstIndex(where: { $0.id == currentID }) {
            if !sameApp && index != 0 {
                let current = choices.remove(at: index)
                choices.insert(current, at: 0)
                selection = 0
            } else {
                selection = index
            }
        } else {
            selection = backwards ? 0 : choices.count - 1
        }
        selecting = true
        moveSelection(backwards: backwards)
    }
    private func focusedWindowID(for pid: pid_t?) -> String? {
        guard let pid else { return nil }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.05)
        guard let focused = attribute(root, kAXFocusedWindowAttribute) else { return nil }
        return entries.first { entry in
            guard entry.pid == pid, let window = entry.window else { return false }
            return CFEqual(window, focused)
        }?.id
    }
    func moveSelection(backwards: Bool) {
        guard selecting, !choices.isEmpty else { return }
        selection = (selection + (backwards ? -1 : 1) + choices.count) % choices.count
        onSelectionChange?()
    }
    func finish(cancel: Bool = false) {
        guard selecting else { return }
        let target = choices.indices.contains(selection) ? choices[selection] : nil
        selecting = false
        choices = []
        originWindowID = nil
        onEndSelection?()
        if !cancel, let target { activate(target) }
    }
    func activate(_ entry: WindowEntry) {
        activationRevision += 1
        lastFocused = entry.id
        onActivate?()
        recent.removeAll { $0 == entry.id }
        recent.insert(entry.id, at: 0)
        activator.activate(entry)
    }
}
