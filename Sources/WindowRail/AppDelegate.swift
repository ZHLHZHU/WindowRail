import AppKit
import SwiftUI
import ApplicationServices
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = WindowModel()
    let preferences = PreferencesModel()
    var preferencesWindow: NSWindow?
    var sidebar: NSPanel!
    var switcher: NSPanel!
    var nativeSwitcher: NativeSwitcherView!
    var railMotion: RailMotion!
    var nativeRail: NativeRailView!
    var status: NSStatusItem!
    var tap: CFMachPort?
    var tapSource: CFRunLoopSource?
    var timer: Timer?
    var previousSidebarHeight: CGFloat = 0
    var sidebarVisible = false
    var edgeReveal = EdgeReveal()
    var edgeTimer: Timer?
    var sidebarScreen: NSScreen?
    var consumedKeys = Set<Int64>()
    private let keyboardLog = Logger(subsystem: "local.windowrail.app", category: "switchTiming")
    func applicationDidFinishLaunching(_ notification: Notification) {
        SwitchTiming.record("Diagnostic tracing enabled")
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = AppArtwork.menuBarIcon()
        status.isVisible = preferences.showMenuBarIcon
        preferences.onMenuBarVisibilityChanged = { [weak self] visible in self?.status.isVisible = visible }
        sidebar = panel(width: 174, height: 700)
        sidebar.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        let railContent = NativeRailView(model: model, settings: { [weak self] in self?.openPermissions() })
        nativeRail = railContent
        configureLocalizedMenus()
        preferences.onLanguageChanged = { [weak self] language in
            L10n.setLanguage(language)
            self?.refreshLocalizedUI()
        }
        railMotion = RailMotion(content: railContent)
        sidebar.contentView = railMotion.clip
        railMotion.clip.onMouseEntered = { [weak self] in
            guard let self, !self.model.selecting, !self.sidebarVisible else { return }
            self.edgeReveal.setVisible(true)
            self.setSidebarVisible(true)
        }
        nativeRail.onContentChanged = { [weak self] in self?.resizeSidebarIfNeeded() }
        positionSidebar()
        sidebar.isMovableByWindowBackground = false
        sidebar.orderOut(nil)
        switcher = panel(width: 460, height: 500, searchable: true)
        switcher.isMovableByWindowBackground = false
        switcher.acceptsMouseMovedEvents = true
        nativeSwitcher = NativeSwitcherView(frame: switcher.contentView!.bounds)
        switcher.contentView = nativeSwitcher
        model.onActivate = { [weak self] in
            self?.edgeReveal.setVisible(false)
            self?.setSidebarVisible(false)
        }
        model.onSelectionChange = { [weak self] in self?.showSwitcher() }
        model.onSearchStart = { [weak self] in self?.nativeSwitcher.focusSearch() }
        model.onEndSelection = { [weak self] in
            self?.nativeSwitcher.endSearchEditing()
            self?.switcher.orderOut(nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(switcherResignedKey),
            name: NSWindow.didResignKeyNotification, object: switcher)
        model.refresh()
        positionSidebar()
        railMotion.prepareHidden()
        collapseSidebar()
        startKeyboard()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard !self.railMotion.animating else { return }
            self.model.refresh()
            self.resizeSidebarIfNeeded()
            if self.model.trusted && self.tap == nil { self.startKeyboard() }
        }
        edgeTimer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            self?.model.sampleFocus()
            self?.updateEdgeReveal()
        }
        if let edgeTimer { RunLoop.main.add(edgeTimer, forMode: .common) }
        if CommandLine.arguments.contains("--ui-test") {
            edgeReveal.setVisible(true)
            setSidebarVisible(true)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshPreferences), name: NSApplication.didBecomeActiveNotification, object: nil)
        if CommandLine.arguments.contains("--settings") { showPreferences() }
    }
    func configureLocalizedMenus() {
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.text(.settingsOpen), action: #selector(showPreferences), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: L10n.text(.sidebarToggle), action: #selector(toggleSidebar), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text(.accessibilityOpen), action: #selector(openPermissions), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text(.keyboardRetry), action: #selector(retryKeyboard), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: L10n.text(.appQuit), action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        status.menu = menu
        let sidebarMenu = NSMenu()
        sidebarMenu.addItem(withTitle: L10n.text(.settingsOpen), action: #selector(showPreferences), keyEquivalent: "")
        sidebarMenu.addItem(withTitle: L10n.text(.appQuit), action: #selector(quit), keyEquivalent: "")
        for item in sidebarMenu.items { item.target = self }
        nativeRail.menu = sidebarMenu
    }
    func refreshLocalizedUI() {
        configureLocalizedMenus()
        preferencesWindow?.title = L10n.text(.settingsTitle)
        model.refreshLocalizedGroups()
        nativeSwitcher = NativeSwitcherView(frame: switcher.contentView!.bounds)
        switcher.contentView = nativeSwitcher
        nativeSwitcher.update(from: model)
    }
    @objc func refreshPreferences() { preferences.refreshLoginStatus() }
    @objc func showPreferences() {
        if preferencesWindow == nil {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: PreferencesView.windowSize), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = L10n.text(.settingsTitle)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PreferencesView(preferences: preferences,
                openPermissions: { [weak self] in self?.openPermissions() },
                quit: { [weak self] in self?.quit() }))
            window.center()
            preferencesWindow = window
        }
        preferences.refreshLoginStatus()
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreferences()
        return false
    }
    func panel(width: CGFloat, height: CGFloat, searchable: Bool = false) -> NSPanel {
        let panelType: NSPanel.Type = searchable ? SwitcherPanel.self : NSPanel.self
        let panel = panelType.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        return panel
    }
    func sidebarHeight(in frame: NSRect) -> CGFloat {
        return min(frame.height - 16, nativeRail.preferredHeight)
    }
    func resizeSidebarIfNeeded() {
        guard let frame = (sidebarScreen ?? NSScreen.main)?.visibleFrame else { return }
        let height = sidebarHeight(in: frame)
        guard !railMotion.animating, height != previousSidebarHeight else { return }
        let old = sidebar.frame
        sidebar.setFrame(NSRect(x: old.minX, y: frame.midY - height / 2, width: sidebarVisible || railMotion.animating ? 174 : 1, height: height), display: true)
        railMotion.resize(sidebar.frame.size)
        previousSidebarHeight = height
    }
    func positionSidebar() {
        guard let frame = (sidebarScreen ?? NSScreen.main)?.visibleFrame else { return }
        let height = sidebarHeight(in: frame)
        previousSidebarHeight = height
        sidebar.setFrame(NSRect(x: (sidebarScreen ?? NSScreen.main)?.frame.minX ?? frame.minX, y: frame.midY - height / 2, width: sidebarVisible || railMotion.animating ? 174 : 1, height: height), display: true)
        railMotion.resize(sidebar.frame.size)
    }
    @objc func spaceChanged() {
        guard !railMotion.animating else { return }
        model.refresh()
        resizeSidebarIfNeeded()
    }
    @objc func screenChanged() {
        sidebarScreen = nil
        edgeReveal.setVisible(false)
        setSidebarVisible(false)
        positionSidebar()
    }
    func showSwitcher() {
        if model.searching && switcher.isVisible && switcher.frame.height < 240 {
            var frame = switcher.frame
            frame.origin.y -= (240 - frame.height) / 2
            frame.size.height = 240
            switcher.setFrame(frame, display: false)
        }
        nativeSwitcher.update(from: model)
        SwitchTiming.record("Picker highlight \(model.selection + 1)/\(model.choices.count)")
        guard !switcher.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let height = min(frame.height - 80, CGFloat(model.choices.count * 53 + 70), 580)
        SwitchTiming.record("Presenting switcher")
        switcher.setFrame(NSRect(x: frame.midX - 230, y: frame.midY - height / 2, width: 460, height: height), display: false)
        switcher.orderFrontRegardless()
        SwitchTiming.record("Switcher ordered front")
    }
    @objc func switcherResignedKey() {
        if model.searching { model.finish(cancel: true) }
    }
    func collapseSidebar() {
        guard !sidebarVisible else { return }
        sidebar.alphaValue = 0
        sidebar.hasShadow = false
        positionSidebar()
        // Keep an invisible one-point input window at the edge, like Contexts.
        sidebar.orderFrontRegardless()
    }
    func setSidebarVisible(_ visible: Bool) {
        guard sidebarVisible != visible else { return }
        let wasCollapsed = sidebar.frame.width <= 1
        sidebarVisible = visible
        if visible {
            if wasCollapsed {
                positionSidebar()
                railMotion.prepareHidden()
            }
            sidebar.alphaValue = 1
            sidebar.hasShadow = true
            sidebar.orderFrontRegardless()
        }
        railMotion.setVisible(visible) { [weak self] in
            guard let self else { return }
            if !self.sidebarVisible { self.collapseSidebar() }
            else { self.resizeSidebarIfNeeded() }
        }
    }
    func updateEdgeReveal() {
        guard !nativeRail.isTrackingRowMenu else { return }
        if CommandLine.arguments.contains("--ui-test") { return }
        if model.selecting {
            edgeReveal.setVisible(false)
            setSidebarVisible(false)
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
        let nearEdge: Bool
        if let screen {
            nearEdge = mouse.x <= screen.frame.minX + 2
                && mouse.y >= screen.visibleFrame.minY + 8
                && mouse.y <= screen.visibleFrame.maxY - 8
            if nearEdge && !sidebarVisible { sidebarScreen = screen }
        } else {
            nearEdge = false
        }
        if nearEdge && !sidebarVisible {
            // Native tracking is immediate; polling is a fallback for alpha-zero
            // trigger windows and switching monitors. Do not wait for Dock's delay.
            edgeReveal.setVisible(true)
            setSidebarVisible(true)
            return
        }
        // Keep a small tolerance around the panel while crossing its border.
        let inside = sidebarVisible && sidebar.frame.insetBy(dx: -8, dy: -8).contains(mouse)
        let visible = edgeReveal.update(nearEdge: nearEdge, insidePanel: inside, now: ProcessInfo.processInfo.systemUptime)
        setSidebarVisible(visible)
    }
    @objc func toggleSidebar() {
        let visible = !sidebarVisible
        if visible {
            let mouse = NSEvent.mouseLocation
            sidebarScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        }
        edgeReveal.setVisible(visible)
        setSidebarVisible(visible)
    }
    @objc func openPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func retryKeyboard() { startKeyboard() }
    @objc func quit() { NSApp.terminate(nil) }
    func startKeyboard() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            return Unmanaged<AppDelegate>.fromOpaque(info).takeUnretainedValue().handle(type: type, event: event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { model.keyboardReady = false; return }
        tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        model.keyboardReady = true
    }
    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            keyboardLog.notice("Keyboard tap was disabled (event \(type.rawValue))")
            model.finish(cancel: true)
            consumedKeys.removeAll()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let command = event.flags.contains(.maskCommand)
        if type == .flagsChanged && !command && model.hasSwitchGesture {
            let arrival = DispatchTime.now().uptimeNanoseconds
            SwitchTiming.record("Command released, input age \(SwitchTiming.milliseconds(since: event.timestamp)) ms")
            if arrival > event.timestamp {
                let delay = (arrival - event.timestamp) / 1_000_000
                if delay >= 100 { keyboardLog.notice("Switch confirmation input arrived \(delay) ms late") }
            }
            model.releaseCommand()
            SwitchTiming.record("Command release processed")
            let elapsed = (DispatchTime.now().uptimeNanoseconds - arrival) / 1_000_000
            if elapsed >= 100 { keyboardLog.notice("Switch confirmation handler took \(elapsed) ms") }
        }
        if type == .keyUp && consumedKeys.remove(code) != nil { return nil }
        if type == .keyDown, command, code == 3,
           !event.flags.contains(.maskAlternate), !event.flags.contains(.maskControl), model.hasSwitchGesture {
            model.beginSearch()
            consumedKeys.insert(code)
            return nil
        }
        // Search editing (including IME candidate navigation) belongs to AppKit.
        // Never consume its Return/Escape/arrows in the global keyboard tap.
        if model.searching { return Unmanaged.passUnretained(event) }
        if type == .keyDown {
            if model.hasSwitchGesture && code == 53 {
                model.finish(cancel: true)
                consumedKeys.insert(code)
                return nil
            }
            if command && model.hasSwitchGesture && (code == 125 || code == 126) {
                SwitchTiming.record("Arrow received, input age \(SwitchTiming.milliseconds(since: event.timestamp)) ms")
                model.moveSelection(backwards: code == 126)
                consumedKeys.insert(code)
                return nil
            }
            if command && !event.flags.contains(.maskAlternate) && !event.flags.contains(.maskControl) && (code == 48 || code == 50) {
                let shortcut = code == 50 ? "same-app" : "all windows"
                SwitchTiming.record("Shortcut \(shortcut) received, input age \(SwitchTiming.milliseconds(since: event.timestamp)) ms")
                if code == 50 && !model.hasSwitchGesture && event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                    return consumedKeys.contains(code) ? nil : Unmanaged.passUnretained(event)
                }
                let handled = model.step(sameApp: code == 50, backwards: event.flags.contains(.maskShift))
                SwitchTiming.record("Shortcut processed, handled: \(handled), selection active: \(model.selecting)")
                if handled { consumedKeys.insert(code); return nil }
            }
        }
        return Unmanaged.passUnretained(event)
    }
}
