// Documentation previews. Only these fictional fixtures are rendered; no live scan runs.
import AppKit
import SwiftUI
import ApplicationServices

final class DemoApplication: NSRunningApplication, @unchecked Sendable {
    let demoName: String
    let demoIcon: NSImage
    init(_ name: String, symbol: String, color: NSColor) {
        demoName = name
        demoIcon = NSImage(size: NSSize(width: 32, height: 32))
        super.init()
        demoIcon.lockFocus()
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 30, height: 30), xRadius: 7, yRadius: 7).fill()
        let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(paletteColors: [.white]))!
        glyph.draw(in: NSRect(x: 7, y: 7, width: 18, height: 18))
        demoIcon.unlockFocus()
    }
    override var localizedName: String? { demoName }
    override var icon: NSImage? { demoIcon }
    override var processIdentifier: pid_t { 99999 }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.regular)
    NSApp.appearance = NSAppearance(named: .darkAqua)
    let chinese = CommandLine.arguments[2] == "zh-Hans"
    func demo(_ en: String, _ zh: String) -> String { chinese ? zh : en }
    let browser = DemoApplication(demo("Browser", "浏览器"), symbol: "globe", color: .systemBlue)
    let editor = DemoApplication(demo("Editor", "代码编辑器"), symbol: "chevron.left.forwardslash.chevron.right", color: .systemPurple)
    let notes = DemoApplication(demo("Notes", "笔记"), symbol: "note.text", color: .systemOrange)
    let files = DemoApplication(demo("Files", "文件"), symbol: "folder", color: .systemCyan)
    let music = DemoApplication(demo("Music", "音乐"), symbol: "music.note", color: .systemPink)
    let model = WindowModel()
    func row(_ id: String, _ title: String, _ app: NSRunningApplication) -> WindowEntry {
        WindowEntry(id: id, pid: app.processIdentifier, app: app, window: nil, title: title)
    }
    let samples = [row("docs", demo("Design notes · Demo Project", "设计文档 · 示例项目"), browser), row("code", "Welcome.swift — DemoApp", editor), row("notes", demo("Weekly plan", "本周计划"), notes), row("files", demo("Sample files", "示例文件"), files)]
    model.groups = [
        SidebarGroup(id: "apps", title: L10n.text("group.apps"), entries: [row("music", demo("Music", "音乐"), music)]),
        SidebarGroup(id: "full", title: L10n.text("group.fullscreen"), entries: []),
        SidebarGroup(id: "desktop:1", title: L10n.format("group.desktop", 1), entries: samples),
        SidebarGroup(id: "desktop:2", title: L10n.format("group.desktop", 2), entries: [row("ideas", demo("Ideas", "灵感收集"), notes)])
    ]
    model.trusted = true
    model.choices = samples
    model.selection = 1
    model.originWindowID = "docs"
    let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    func capture(_ view: NSView, size: NSSize, name: String) {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35))
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let region = view.bounds
        let bitmap = view.bitmapImageRepForCachingDisplay(in: region)!
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: region, to: bitmap)
        }
        try! bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
        window.orderOut(nil)
    }
    capture(NativeRailView(model: model, settings: {}), size: NSSize(width: 174, height: 329), name: "sidebar.png")
    capture(NSHostingView(rootView: SwitcherView(model: model)), size: NSSize(width: 460, height: 210), name: "switcher.png")
    let domain = "WindowRail.Documentation.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    let preferences = PreferencesModel(defaults: defaults)
    let info = NSDictionary(contentsOfFile: "Resources/Info.plist")!
    let previewVersion = info["CFBundleShortVersionString"] as! String
    capture(NSHostingView(rootView: PreferencesView(version: previewVersion, preferences: preferences, openPermissions: {}, quit: {}).environment(\.controlActiveState, .active)), size: PreferencesView.windowSize, name: "settings.png")
    defaults.removePersistentDomain(forName: domain)
    print("Rendered three previews from fictional fixtures only.")
}
