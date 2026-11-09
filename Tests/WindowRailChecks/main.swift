import AppKit
import ApplicationServices

func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) { precondition(lhs == rhs, "Expected equal values", file: file, line: line) }
func expectTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(value, "Expected true", file: file, line: line) }
func expectFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(!value, "Expected false", file: file, line: line) }
func expectNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { precondition(value == nil, "Expected nil", file: file, line: line) }
func expectNotNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { precondition(value != nil, "Expected a value", file: file, line: line) }

final class WindowRailChecks {
    private func entry(_ id: String, spaces: [UInt64] = [], window: Bool = true) -> WindowEntry {
        WindowEntry(id: id, pid: getpid(), app: .current,
                    window: window ? AXUIElementCreateSystemWide() : nil,
                    title: id, spaceIDs: spaces)
    }

    func testSpaceGroupingDoesNotInventMembershipOrDuplicatePinnedWindows() {
        let spaces = [
            DesktopSpace(id: 10, title: "Desktop 1", fullScreen: false),
            DesktopSpace(id: 20, title: "Desktop 2", fullScreen: false),
            DesktopSpace(id: 30, title: "Full Screen", fullScreen: true)
        ]
        let groups = SpaceCatalog.group([
            entry("app", window: false), entry("second", spaces: [20]),
            entry("pinned", spaces: [10, 20]), entry("full", spaces: [30]), entry("unknown")
        ], spaces: spaces)
        expectEqual(groups.map(\.id), ["apps", "fullscreen", "space:10", "space:20", "unknown"])
        expectEqual(groups[0].entries.map(\.id), ["app"])
        expectEqual(Set(groups[1].entries.map(\.id)), ["pinned", "full"])
        expectTrue(groups[2].entries.isEmpty)
        expectEqual(groups[3].entries.map(\.id), ["second"])
        expectEqual(groups[4].entries.map(\.id), ["unknown"])
    }

    func testUnavailableSpaceAPIUsesExplicitFallback() {
        let groups = SpaceCatalog.group([entry("unresolved", spaces: [42])], spaces: [])
        expectEqual(groups.last?.id, "unknown")
        expectEqual(groups.last?.entries.map(\.id), ["unresolved"])
    }

    func testSelectionWrapsWithoutMovingCurrentWindowMarker() {
        let model = WindowModel()
        model.selecting = true
        model.choices = [entry("first"), entry("origin")]
        model.selection = 1
        model.originWindowID = "origin"
        model.moveSelection(backwards: false)
        expectEqual(model.selection, 0)
        expectEqual(model.originWindowID, "origin")
        model.moveSelection(backwards: true)
        expectEqual(model.selection, 1)
        model.finish(cancel: true)
        expectNil(model.originWindowID)
        expectTrue(model.choices.isEmpty)
    }

    func testArrowRoutingPreservesAppShortcutsOutsidePicker() {
        _ = NSApplication.shared
        let controller = AppDelegate()
        func key(_ code: CGKeyCode, down: Bool = true) -> CGEvent {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            event.flags = [.maskCommand]
            return event
        }
        expectNotNil(controller.handle(type: .keyDown, event: key(125)))
        controller.model.choices = [entry("one"), entry("two")]
        controller.model.selecting = true
        expectNil(controller.handle(type: .keyDown, event: key(125)))
        expectEqual(controller.model.selection, 1)
        expectNil(controller.handle(type: .keyUp, event: key(125, down: false)))
        expectNil(controller.handle(type: .keyDown, event: key(53)))
        expectFalse(controller.model.selecting)
        expectNotNil(controller.handle(type: .keyDown, event: key(126)))
    }

    func testExitGracePeriodAndReentry() {
        var state = EdgeReveal()
        state.setVisible(true)
        expectTrue(state.update(nearEdge: false, insidePanel: false, now: 1))
        expectTrue(state.update(nearEdge: false, insidePanel: true, now: 1.1))
        expectTrue(state.update(nearEdge: false, insidePanel: false, now: 2))
        expectFalse(state.update(nearEdge: false, insidePanel: false, now: 2.26))
    }

    func testMenuBarPreferencePersistsAndNotifies() {
        let domain = "WindowRailTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = PreferencesModel(defaults: defaults)
        expectTrue(preferences.showMenuBarIcon)
        var reported: Bool?
        preferences.onMenuBarVisibilityChanged = { reported = $0 }
        preferences.setMenuBarIcon(false)
        expectEqual(reported, false)
        expectFalse(PreferencesModel(defaults: defaults).showMenuBarIcon)
    }
}

let checks = WindowRailChecks()
checks.testSpaceGroupingDoesNotInventMembershipOrDuplicatePinnedWindows()
checks.testUnavailableSpaceAPIUsesExplicitFallback()
checks.testSelectionWrapsWithoutMovingCurrentWindowMarker()
checks.testArrowRoutingPreservesAppShortcutsOutsidePicker()
checks.testExitGracePeriodAndReentry()
checks.testMenuBarPreferencePersistsAndNotifies()
print("PASS: 6 regression checks (grouping, fallback, origin marker, key routing, edge delay, preferences)")

expectEqual(L10n.text(.settingsOpen, language: "en"), "Settings…")
expectEqual(L10n.text(.settingsOpen, language: "zh-Hans"), "设置…")
expectEqual(L10n.text(.settingsOpen, language: "fr"), "Settings…")
expectEqual(L10n.text(.windowCurrent, language: "en"), "Current")
print("PASS: English, Simplified Chinese and unsupported-language fallback")

// A selected language can exist while an individual key is still untranslated.
let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: fixture) }
for (language, contents) in [
    "en": "\"app.quit\" = \"English fallback\";\n",
    "zh-Hans": "\"settings.open\" = \"设置\";\n"
] {
    let directory = fixture.appendingPathComponent("\(language).lproj")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try contents.write(to: directory.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
}
let fixtureBundle = Bundle(path: fixture.path)!
expectEqual(L10n.text(.appQuit, language: "zh-Hans", bundle: fixtureBundle), "English fallback")
expectEqual(L10n.text(.settingsOpen, language: "zh-Hans", bundle: fixtureBundle), "设置")

let languageDomain = "WindowRailLanguageTests.\(UUID().uuidString)"
let languageDefaults = UserDefaults(suiteName: languageDomain)!
defer { languageDefaults.removePersistentDomain(forName: languageDomain) }
let originalChoice = L10n.languageChoice
defer { L10n.setLanguage(originalChoice) }
let languagePreferences = PreferencesModel(defaults: languageDefaults)
expectEqual(languagePreferences.language, "")
languagePreferences.onLanguageChanged = { L10n.setLanguage($0) }
languagePreferences.setLanguage("en")
expectEqual(PreferencesModel(defaults: languageDefaults).language, "en")
expectEqual(L10n.text(.appQuit), "Quit WindowRail")
let languageModel = WindowModel()
languageModel.groups = [SidebarGroup(id: "space:10", title: "Desktop 1", entries: [])]
languagePreferences.setLanguage("zh-Hans")
languageModel.refreshLocalizedGroups()
expectEqual(L10n.text(.appQuit), "退出 WindowRail")
expectEqual(languageModel.groups.first?.title, "桌面 1")
expectEqual(L10n.format(.groupDesktop, 2), "桌面 2")
languagePreferences.setLanguage("unknown-language")
expectEqual(languagePreferences.language, "")
expectEqual(PreferencesModel(defaults: languageDefaults).language, "")
expectEqual(L10n.currentLanguage, L10n.languageIdentifier(for: ""))
expectEqual(Set(L10n.availableLanguages), Set(["en", "zh-Hans"]))
print("PASS: per-key fallback, live language change, persisted selection and system-language reset")

// Reproduce a production .app declaring languages in Info.plist as well as .lproj.
let packaged = fixture.appendingPathComponent("Packaged.bundle")
try FileManager.default.createDirectory(at: packaged, withIntermediateDirectories: true)
for language in ["en", "zh-Hans"] {
    try FileManager.default.createDirectory(at: packaged.appendingPathComponent("\(language).lproj"), withIntermediateDirectories: true)
}
let packagedInfo: [String: Any] = [
    "CFBundleIdentifier": "local.windowrail.localization-test",
    "CFBundleLocalizations": ["en", "en", "zh-Hans", "zh-Hans"],
    "CFBundleDevelopmentRegion": "en"
]
try PropertyListSerialization.data(fromPropertyList: packagedInfo, format: .xml, options: 0).write(to: packaged.appendingPathComponent("Info.plist"))
let packagedBundle = Bundle(path: packaged.path)!
expectEqual(L10n.languages(in: packagedBundle), ["en", "zh-Hans"])
expectEqual(L10n.availableLanguages.count, Set(L10n.availableLanguages).count)
print("PASS: packaged-app languages are unique even when metadata and resources overlap")

// Inspect the native menus attached to the rows without dispatching a click or
// sending any command to a running application.
do {
    let saved = L10n.languageChoice
    L10n.setLanguage("en")
    defer { L10n.setLanguage(saved) }
    let model = WindowModel()
    model.trusted = true
    let window = WindowEntry(id: "test-window", pid: getpid(), app: .current,
                             window: AXUIElementCreateSystemWide(), title: "Fixture Window")
    let app = WindowEntry(id: "test-app", pid: getpid(), app: .current,
                          window: nil, title: "Fixture App")
    model.groups = [SidebarGroup(id: "fixture", title: "Fixture", entries: [window, app])]
    let rail = NativeRailView(model: model, settings: {})
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    func buttons(in view: NSView) -> [NSButton] {
        if let button = view as? NSButton { return [button] }
        return view.subviews.flatMap(buttons(in:))
    }
    let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
        timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
    let rows = buttons(in: rail)
    let windowMenu = rows.first { $0.title == window.title }!.menu(for: event)!
    let appMenu = rows.first { $0.title == app.title }!.menu(for: event)!
    expectEqual(windowMenu.items.map(\.tag), [WindowCommand.close.rawValue, WindowCommand.quit.rawValue, WindowCommand.minimize.rawValue])
    expectEqual(appMenu.items.map(\.tag), [WindowCommand.quit.rawValue])
    expectTrue(windowMenu.items.allSatisfy { ($0.representedObject as? WindowEntry)?.id == window.id })
    expectEqual((appMenu.items.first?.representedObject as? WindowEntry)?.id, app.id)
    expectFalse(windowMenu.items[0].isEnabled)
    expectFalse(windowMenu.items[2].isEnabled)
    windowMenu.delegate?.menuWillOpen?(windowMenu)
    expectTrue(rail.isTrackingRowMenu)
    windowMenu.delegate?.menuDidClose?(windowMenu)
    expectFalse(rail.isTrackingRowMenu)
    print("PASS: native sidebar menus keep the clicked target and disable unsupported window actions")
}
