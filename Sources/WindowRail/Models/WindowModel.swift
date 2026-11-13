import AppKit
import SwiftUI
import ApplicationServices
import OSLog

final class WindowModel: ObservableObject {
    @Published var entries: [WindowEntry] = []
    @Published var groups: [SidebarGroup] = []
    let spaceCatalog = SpaceCatalog()
    private let activateWindow: (WindowEntry) -> Void

    init(activateWindow: @escaping (WindowEntry) -> Void = WindowActivator().activate) {
        self.activateWindow = activateWindow
    }
    var onActivate: (() -> Void)?
    @Published var trusted = AXIsProcessTrusted()
    @Published var keyboardReady = false
    @Published var selecting = false
    @Published var choices: [WindowEntry] = []
    @Published var selection = 0
    @Published var originWindowID: String?
    private(set) var searching = false
    private(set) var searchQuery = ""
    private var searchChoices: [WindowEntry] = []
    private var searchRequested = false
    var onSearchStart: (() -> Void)?
    var recent: [String] = []
    var previousMembership: [String: [UInt64]] = [:]
    private let scanQueue = DispatchQueue(label: "local.windowrail.scan", qos: .userInitiated)
    private var refreshInProgress = false
    private let focusQueue = DispatchQueue(label: "local.windowrail.focus", qos: .userInitiated)
    private var focusQueryInProgress = false
    private var pendingSameApp: (id: UUID, pid: pid_t, steps: Int, released: Bool)?
    var hasSwitchGesture: Bool { selecting || pendingSameApp?.released == false }
    private var nextFocusQuery: TimeInterval = 0
    private var lastFocused: String?
    private var pendingFocus: (id: String, pid: pid_t, sourcePID: pid_t?, until: TimeInterval)?
    private var activationRevision = 0
    private var focusTiming: (id: String, start: TimeInterval)?
    private let timingLog = Logger(subsystem: "local.windowrail.app", category: "switchTiming")
    var onSelectionChange: (() -> Void)?
    var onEndSelection: (() -> Void)?

    func refresh() {
        trusted = AXIsProcessTrusted()
        guard !selecting, !refreshInProgress else { return }
        refreshInProgress = true
        let trusted = self.trusted
        let savedMembership = previousMembership
        scanQueue.async { [self] in
            var scanMembership = savedMembership
            spaceCatalog.refresh()
            var result: [WindowEntry] = []
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            for app in NSWorkspace.shared.runningApplications where app.processIdentifier != getpid()
                && (app.activationPolicy == .regular || app.processIdentifier == frontPID) {
                let windows = trusted
                    ? readWindows(of: app, includeFocused: app.processIdentifier == frontPID).entries : []
                if windows.isEmpty {
                    result.append(WindowEntry(id: "app:\(app.processIdentifier)", pid: app.processIdentifier,
                                              app: app, window: nil, title: app.localizedName ?? L10n.text(.appFallback)))
                }
                for var entry in windows {
                    if !entry.spaceIDs.isEmpty { scanMembership[entry.id] = entry.spaceIDs }
                    else { entry.spaceIDs = scanMembership[entry.id] ?? [] }
                    result.append(entry)
                }
            }
            let scannedEntries = result
            let scannedMembership = scanMembership
            DispatchQueue.main.async { [self] in
                defer { refreshInProgress = false }
                guard !selecting else { return }
                let result = scannedEntries
                previousMembership = scannedMembership
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
    private func readWindows(of app: NSRunningApplication, includeFocused: Bool) -> (entries: [WindowEntry], focusedID: String?) {
        let pid = app.processIdentifier
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.08)
        var windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let focused = includeFocused ? attribute(root, kAXFocusedWindowAttribute) : nil
        if let focused, CFGetTypeID(focused) == AXUIElementGetTypeID(),
           !windows.contains(where: { CFEqual($0, focused) }) {
            windows.insert(focused as! AXUIElement, at: 0)
        }
        var result: [WindowEntry] = []
        var focusedID: String?
        var seen = Set<String>()
        for window in windows {
            AXUIElementSetMessagingTimeout(window, 0.05)
            let subrole = attribute(window, kAXSubroleAttribute) as? String
            let windowID = spaceCatalog.id(for: window)
            let isFocused = focused.map { CFEqual($0, window) } ?? false
            if subrole != kAXStandardWindowSubrole && subrole != kAXDialogSubrole {
                // Some apps leave the subrole unset on otherwise ordinary windows.
                guard windowID != nil, subrole == nil || subrole == kAXUnknownSubrole,
                      (attribute(window, kAXRoleAttribute) as? String) == kAXWindowRole,
                      isFocused || attribute(window, kAXCloseButtonAttribute) != nil else { continue }
            }
            let id = "\(pid):\(windowID.map(String.init) ?? String(CFHash(window)))"
            if isFocused { focusedID = id }
            guard seen.insert(id).inserted else { continue }
            let title = (attribute(window, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? app.localizedName ?? L10n.text(.windowFallback)
            result.append(WindowEntry(id: id, pid: pid, app: app, window: window, title: title,
                fullScreen: (attribute(window, "AXFullScreen") as? Bool) == true,
                spaceIDs: spaceCatalog.memberships(for: windowID)))
        }
        if includeFocused {
            SwitchTiming.record("Front application \(pid) exposed \(windows.count) AX windows, usable \(result.count)")
        }
        return (result, focusedID)
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
    func step(sameApp: Bool, backwards: Bool) -> Bool {
        guard trusted else { return false }
        if hasSwitchGesture {
            moveSelection(backwards: backwards)
            return true
        }
        let frontApp = NSWorkspace.shared.frontmostApplication
        let actualPID = frontApp?.processIdentifier
        let pending = expectedFocus(frontPID: actualPID)
        let frontPID = pending?.pid ?? actualPID
        let focusedID = pending?.id ?? entries.first { $0.pid == frontPID && $0.id == lastFocused }?.id
        if sameApp, let frontApp, frontApp.processIdentifier != getpid(),
           entries.filter({ $0.pid == frontPID && $0.window != nil }).count < 2 {
            // Refresh a thin cache without losing the gesture's movement or release.
            if pendingSameApp?.pid == frontApp.processIdentifier {
                pendingSameApp?.steps = backwards ? -1 : 1
                pendingSameApp?.released = false
            } else {
                refreshSameApp(frontApp, backwards: backwards)
            }
            return true
        }
        pendingSameApp = nil
        return beginSelection(sameApp: sameApp, frontPID: frontPID, focusedID: focusedID,
                              backwards: backwards)
    }

    private func refreshSameApp(_ app: NSRunningApplication, backwards: Bool) {
        let id = UUID()
        let pid = app.processIdentifier
        pendingSameApp = (id, pid, backwards ? -1 : 1, false)
        let revision = activationRevision
        focusQueue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.readWindows(of: app, includeFocused: true)
            DispatchQueue.main.async { [weak self] in
                guard let self, let gesture = self.pendingSameApp, gesture.id == id else { return }
                self.pendingSameApp = nil
                let wantsSearch = self.searchRequested
                self.searchRequested = false
                guard self.trusted, !self.selecting, self.activationRevision == revision,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                      !snapshot.entries.isEmpty else { return }
                self.entries = self.entries.filter { $0.pid != pid } + snapshot.entries
                self.beginSelection(sameApp: true, frontPID: pid, focusedID: snapshot.focusedID,
                                    backwards: gesture.steps < 0, steps: gesture.steps,
                                    present: wantsSearch || !gesture.released)
                if wantsSearch { self.beginSearch() }
                else if gesture.released { self.finish() }
            }
        }
    }

    @discardableResult
    func beginSelection(sameApp: Bool, frontPID: pid_t?, focusedID: String?, backwards: Bool,
                        steps: Int? = nil, present: Bool = true) -> Bool {
        let candidates = entries.filter { !sameApp || $0.pid == frontPID }
        guard !candidates.isEmpty else { return false }
        searching = false
        searchRequested = false
        searchQuery = ""
        searchChoices = []

        // Freeze recency for this gesture. The next gesture starts from the updated order.
        let rank = Dictionary(uniqueKeysWithValues: recent.enumerated().map { ($0.element, $0.offset) })
        choices = candidates.enumerated().sorted { first, second in
            let a = rank[first.element.id] ?? Int.max
            let b = rank[second.element.id] ?? Int.max
            return a == b ? first.offset < second.offset : a < b
        }.map(\.element)

        let frontChoices = choices.filter { $0.pid == frontPID }
        let currentID = focusedID
            ?? recent.first { id in frontChoices.contains { $0.id == id } }
            ?? frontChoices.first?.id
        originWindowID = sameApp ? currentID : nil
        if let index = choices.firstIndex(where: { $0.id == currentID }) {
            if index != 0 {
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
        let offset = (steps ?? (backwards ? -1 : 1)) % choices.count
        selection = (selection + offset + choices.count) % choices.count
        if present { onSelectionChange?() }
        return true
    }
    private func expectedFocus(frontPID: pid_t?) -> (id: String, pid: pid_t)? {
        guard let pendingFocus,
              ProcessInfo.processInfo.systemUptime < pendingFocus.until,
              frontPID == pendingFocus.sourcePID || frontPID == pendingFocus.pid else { return nil }
        return (pendingFocus.id, pendingFocus.pid)
    }

    func sampleFocus() {
        let now = ProcessInfo.processInfo.systemUptime
        if let timing = focusTiming, now - timing.start > 3 {
            timingLog.notice("Switch \(self.activationRevision) focus was not confirmed within 3000 ms")
            focusTiming = nil
        }
        guard trusted, !selecting, !focusQueryInProgress, now >= nextFocusQuery,
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        nextFocusQuery = now + 0.12
        let candidates = entries.filter { $0.pid == pid }
        guard !candidates.isEmpty else { return }
        let revision = activationRevision
        focusQueryInProgress = true

        focusQueue.async { [weak self] in
            let root = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(root, 0.05)
            let focused = attribute(root, kAXFocusedWindowAttribute)
            let id = candidates.first { entry in
                guard let window = entry.window, let focused else { return entry.window == nil }
                return CFEqual(window, focused)
            }?.id
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.focusQueryInProgress = false
                guard !self.selecting, revision == self.activationRevision,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                      let id else { return }
                if let expected = self.expectedFocus(frontPID: pid), expected.id != id { return }
                self.pendingFocus = nil
                if let timing = self.focusTiming, timing.id == id {
                    let delay = Int((ProcessInfo.processInfo.systemUptime - timing.start) * 1_000)
                    SwitchTiming.record("Activation \(revision) focus confirmed after \(delay) ms")
                    if delay >= 250 { self.timingLog.notice("Switch \(revision) focus confirmed after \(delay) ms") }
                    self.focusTiming = nil
                }
                if id != self.lastFocused {
                    self.lastFocused = id
                    self.recent.removeAll { $0 == id }
                    self.recent.insert(id, at: 0)
                }
            }
        }
    }

    private func adjacentSelection(backwards: Bool) -> Int {
        (selection + (backwards ? -1 : 1) + choices.count) % choices.count
    }

    func moveSelection(backwards: Bool) {
        if pendingSameApp?.released == false {
            pendingSameApp?.steps += backwards ? -1 : 1
            return
        }
        guard selecting, !choices.isEmpty else { return }
        selection = adjacentSelection(backwards: backwards)
        onSelectionChange?()
    }
    @discardableResult
    func beginSearch() -> Bool {
        guard hasSwitchGesture else { return false }
        guard selecting else { searchRequested = true; return true }
        if !searching {
            searching = true
            searchQuery = ""
            searchChoices = choices
        }
        onSelectionChange?()
        onSearchStart?()
        return true
    }

    func updateSearch(_ query: String) {
        guard selecting, searching else { return }
        let selectedID = choices.indices.contains(selection) ? choices[selection].id : nil
        searchQuery = query
        choices = searchChoices.filter {
            WindowSearch.matches(query, title: $0.title, applicationName: $0.app.localizedName ?? "")
        }
        selection = choices.firstIndex { $0.id == selectedID } ?? 0
        onSelectionChange?()
    }

    func releaseCommand() {
        guard !searching, !searchRequested else { return }
        finish()
    }

    @discardableResult
    func selectChoice(id: String) -> Bool {
        guard selecting, let index = choices.firstIndex(where: { $0.id == id }) else { return false }
        if selection != index {
            selection = index
            onSelectionChange?()
        }
        return true
    }

    @discardableResult
    func confirmChoice(id: String) -> Bool {
        guard selecting, let index = choices.firstIndex(where: { $0.id == id }) else { return false }
        selection = index
        finish()
        return true
    }

    func finish(cancel: Bool = false) {
        if pendingSameApp != nil {
            if cancel { pendingSameApp = nil; searchRequested = false }
            else { pendingSameApp?.released = true }
            return
        }
        guard selecting else { return }
        let target = choices.indices.contains(selection) ? choices[selection] : nil
        let origin = originWindowID
        selecting = false
        searching = false
        searchRequested = false
        searchQuery = ""
        searchChoices = []
        choices = []
        originWindowID = nil
        if !cancel, let target, target.id != origin { activate(target) }
        onEndSelection?()
    }
    func activate(_ entry: WindowEntry) {
        activationRevision += 1
        let now = ProcessInfo.processInfo.systemUptime
        focusTiming = (entry.id, now)
        pendingFocus = (entry.id, entry.pid, NSWorkspace.shared.frontmostApplication?.processIdentifier, now + 0.3)
        lastFocused = entry.id
        recent.removeAll { $0 == entry.id }
        recent.insert(entry.id, at: 0)
        activateWindow(entry)
        onActivate?()
    }
}
