import AppKit
import SwiftUI
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = WindowModel()
    let preferences = PreferencesModel()
    var preferencesWindow: NSWindow?
    var sidebar: NSPanel!
    var switcher: NSPanel!
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "WindowRail")
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.text("settings.open"), action: #selector(showPreferences), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: L10n.text("sidebar.toggle"), action: #selector(toggleSidebar), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text("accessibility.open"), action: #selector(openPermissions), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text("keyboard.retry"), action: #selector(retryKeyboard), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: L10n.text("app.quit"), action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        status.menu = menu
        status.isVisible = preferences.showMenuBarIcon
        preferences.onMenuBarVisibilityChanged = { [weak self] visible in self?.status.isVisible = visible }
        sidebar = panel(width: 174, height: 700)
        sidebar.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        let railContent = NativeRailView(model: model, settings: { [weak self] in self?.openPermissions() })
        nativeRail = railContent
        let sidebarMenu = NSMenu()
        sidebarMenu.addItem(withTitle: L10n.text("settings.open"), action: #selector(showPreferences), keyEquivalent: "")
        sidebarMenu.addItem(withTitle: L10n.text("app.quit"), action: #selector(quit), keyEquivalent: "")
        for item in sidebarMenu.items { item.target = self }
        nativeRail.menu = sidebarMenu
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
        switcher = panel(width: 460, height: 500)
        switcher.contentView = NSHostingView(rootView: SwitcherView(model: model))
        model.onActivate = { [weak self] in
            self?.edgeReveal.setVisible(false)
            self?.setSidebarVisible(false)
        }
        model.onSelectionChange = { [weak self] in self?.showSwitcher() }
        model.onEndSelection = { [weak self] in self?.switcher.orderOut(nil) }
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
        edgeTimer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in self?.updateEdgeReveal() }
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
    @objc func refreshPreferences() { preferences.refreshLoginStatus() }
    @objc func showPreferences() {
        if preferencesWindow == nil {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: PreferencesView.windowSize), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = L10n.text("settings.title")
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
    func panel(width: CGFloat, height: CGFloat) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let height = min(frame.height - 80, CGFloat(model.choices.count * 53 + 70), 580)
        switcher.setFrame(NSRect(x: frame.midX - 230, y: frame.midY - height / 2, width: 460, height: height), display: true)
        switcher.orderFrontRegardless()
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
            model.finish(cancel: true)
            consumedKeys.removeAll()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let command = event.flags.contains(.maskCommand)
        if type == .flagsChanged && !command { model.finish() }
        if type == .keyUp && consumedKeys.remove(code) != nil { return nil }
        if type == .keyDown {
            if model.selecting && code == 53 {
                model.finish(cancel: true)
                consumedKeys.insert(code)
                return nil
            }
            if command && model.selecting && (code == 125 || code == 126) {
                model.moveSelection(backwards: code == 126)
                consumedKeys.insert(code)
                return nil
            }
            if command && !event.flags.contains(.maskAlternate) && !event.flags.contains(.maskControl) && (code == 48 || code == 50) {
                model.step(sameApp: code == 50, backwards: event.flags.contains(.maskShift))
                if model.selecting { consumedKeys.insert(code); return nil }
            }
        }
        return Unmanaged.passUnretained(event)
    }
}
