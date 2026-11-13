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

    func testRapidSwitchingUsesLiveFocusAndRecentOrder() {
        let model = WindowModel()
        model.entries = [entry("a"), entry("b"), entry("c")]
        model.recent = ["c", "b", "a"]

        model.beginSelection(sameApp: false, frontPID: getpid(), focusedID: "c", backwards: false)
        expectEqual(model.choices[model.selection].id, "b")
        model.moveSelection(backwards: false)
        expectEqual(model.choices[model.selection].id, "a")
        model.moveSelection(backwards: true)
        expectEqual(model.choices[model.selection].id, "b")
        model.finish(cancel: true)

        // Window B has just become focused, but the background list has not refreshed.
        model.recent = ["b", "c", "a"]
        model.beginSelection(sameApp: false, frontPID: getpid(), focusedID: "b", backwards: false)
        expectEqual(model.choices[model.selection].id, "c")
        model.finish(cancel: true)

        model.beginSelection(sameApp: false, frontPID: getpid(), focusedID: "a", backwards: false)
        expectEqual(model.choices[model.selection].id, "b")
        model.finish(cancel: true)

        model.entries.reverse()
        model.recent = ["b", "a", "c"]
        for (focused, expected) in [("b", "a"), ("a", "b"), ("b", "a")] {
            model.beginSelection(sameApp: true, frontPID: getpid(), focusedID: focused, backwards: false)
            expectEqual(model.originWindowID, focused)
            expectEqual(model.choices[model.selection].id, expected)
            model.finish(cancel: true)
            model.recent = [expected, focused, "c"]
        }

        model.beginSelection(sameApp: true, frontPID: getpid(), focusedID: "a", backwards: false)
        expectEqual(model.choices[model.selection].id, "b")
        model.moveSelection(backwards: false)
        expectEqual(model.choices[model.selection].id, "c")
        model.finish(cancel: true)
        model.beginSelection(sameApp: true, frontPID: getpid(), focusedID: "a", backwards: true)
        expectEqual(model.choices[model.selection].id, "c")
        model.finish(cancel: true)
    }

    func testSameAppPickerCommitsOnlyOnRelease() {
        var activated: [String] = []
        let model = WindowModel(activateWindow: { activated.append($0.id) })
        model.entries = [entry("c"), entry("a"), entry("b")]
        model.recent = ["a", "b", "c"]
        var panelUpdates = 0
        model.onSelectionChange = { panelUpdates += 1 }
        for (focused, previous) in [("a", "b"), ("b", "a"), ("a", "b")] {
            let before = activated.count
            expectTrue(model.beginSelection(sameApp: true, frontPID: getpid(), focusedID: focused,
                                            backwards: false))
            expectTrue(model.selecting)
            expectEqual(model.choices[model.selection].id, previous)
            expectEqual(activated.count, before)
            model.finish()
            expectEqual(activated.last, previous)
        }
        expectEqual(activated, ["b", "a", "b"])
        expectEqual(panelUpdates, 3)

        // A scan that completes after release commits the buffered choice without flashing a panel.
        model.beginSelection(sameApp: true, frontPID: getpid(), focusedID: "b",
                             backwards: false, steps: 2, present: false)
        model.finish()
        expectEqual(activated.last, "c")
        expectEqual(panelUpdates, 3)
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

    func testHeldCommandRepaintsEverySelection() {
        _ = NSApplication.shared
        let controller = AppDelegate()
        let model = controller.model
        model.trusted = true
        model.entries = [entry("a"), entry("b"), entry("c")]
        model.recent = ["a", "b", "c"]
        let picker = NativeSwitcherView(frame: NSRect(x: 0, y: 0, width: 460, height: 150))
        let panel = NSPanel(contentRect: picker.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = picker
        model.onSelectionChange = { picker.update(from: model) }
        model.beginSelection(sameApp: true, frontPID: getpid(), focusedID: "a", backwards: false)
        func pixels() -> Data {
            let bitmap = picker.bitmapImageRepForCachingDisplay(in: picker.bounds)!
            picker.cacheDisplay(in: picker.bounds, to: bitmap)
            return bitmap.representation(using: .png, properties: [:])!
        }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            picker.appearance = NSAppearance(named: appearance)
            picker.update(from: model)
            var previousPixels = pixels()
            // No run-loop pump between keys: each callback must repaint directly.
            for index in 0..<40 {
                let code: CGKeyCode = index % 4 == 0 ? 125 : 50
                let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
                event.flags = index % 3 == 0 ? [.maskCommand, .maskShift] : [.maskCommand]
                let backwards = code == 50 && event.flags.contains(.maskShift)
                let expected = (model.selection + (backwards ? -1 : 1) + 3) % 3
                expectNil(controller.handle(type: .keyDown, event: event))
                expectEqual(model.selection, expected)
                expectEqual(picker.highlightedIndices, [expected])
                let nextPixels = pixels()
                expectFalse(nextPixels == previousPixels)
                previousPixels = nextPixels
                let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)!
                up.flags = [.maskCommand]
                expectNil(controller.handle(type: .keyUp, event: up))
            }
        }
        model.finish(cancel: true)
    }

    func testPickerMouseConfirmsClickedRowOnlyOnce() {
        _ = NSApplication.shared
        var activated: [String] = []
        var closed = 0
        let model = WindowModel(activateWindow: { activated.append($0.id) })
        model.entries = [entry("a"), entry("b"), entry("c")]
        model.recent = ["a", "b", "c"]
        model.onEndSelection = { closed += 1 }
        let picker = NativeSwitcherView(frame: NSRect(x: 0, y: 0, width: 460, height: 180))
        let panel = NSPanel(contentRect: picker.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = picker
        model.onSelectionChange = { picker.update(from: model) }
        func start() {
            model.recent = ["a", "b", "c"]
            model.beginSelection(sameApp: true, frontPID: getpid(), focusedID: "a", backwards: false)
        }
        let mouse = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [.command], timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        // The icon, title and empty part of the row all receive the first click
        // even though the nonactivating switcher is not the key window.
        for x: CGFloat in [27, 100, 350] {
            start()
            let point = picker.convert(NSPoint(x: x, y: 44 + 2 * 29 + 13), to: picker.superview)
            let target = picker.hitTest(point)!
            expectEqual(target.accessibilityLabel(), "c")
            expectTrue(target.acceptsFirstMouse(for: mouse))
            expectFalse(target.mouseDownCanMoveWindow)
            let count = activated.count
            target.mouseDown(with: mouse)
            expectEqual(activated.count, count + 1)
            expectEqual(activated.last, "c")
            expectFalse(model.selecting)
            model.finish() // Command release after the click must not activate twice.
            expectEqual(activated.count, count + 1)
            expectFalse(target.accessibilityPerformPress()) // Stale/hidden row.
        }
        start()
        let point = picker.convert(NSPoint(x: 350, y: 44 + 13), to: picker.superview)
        let current = picker.hitTest(point)!
        expectEqual(current.accessibilityLabel(), "a")
        expectTrue(current.accessibilityPerformPress())
        expectEqual(activated, ["c", "c", "c"])
        expectEqual(closed, 4)
    }

    func testPickerHoverSelectsWithoutActivating() {
        _ = NSApplication.shared
        var activated: [String] = []
        let model = WindowModel(activateWindow: { activated.append($0.id) })
        model.entries = [entry("a"), entry("b"), entry("c")]
        model.recent = ["a", "b", "c"]
        let picker = NativeSwitcherView(frame: NSRect(x: 0, y: 0, width: 460, height: 180))
        let panel = NSPanel(contentRect: picker.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = picker
        model.onSelectionChange = { picker.update(from: model) }
        model.beginSelection(sameApp: true, frontPID: getpid(), focusedID: "a", backwards: false)
        let point = picker.convert(NSPoint(x: 100, y: 44 + 2 * 29 + 13), to: picker.superview)
        let row = picker.hitTest(point)!
        row.updateTrackingAreas()
        expectTrue(row.trackingAreas.contains { $0.options.contains([.mouseMoved, .activeAlways, .inVisibleRect]) })
        expectFalse(row.trackingAreas.filter { $0.options.contains(.mouseMoved) }
            .contains { $0.options.contains(.mouseEnteredAndExited) })
        expectEqual(picker.highlightedIndices, [1]) // Merely showing the panel keeps keyboard selection.
        let move = NSEvent.mouseEvent(with: .mouseMoved, location: .zero,
            modifierFlags: [.command], timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        row.mouseMoved(with: move)
        expectEqual(model.selection, 2)
        expectEqual(picker.highlightedIndices, [2])
        expectEqual(model.originWindowID, "a")
        expectTrue(activated.isEmpty)
        model.moveSelection(backwards: true)
        expectEqual(picker.highlightedIndices, [1])
        row.mouseMoved(with: move)
        model.finish()
        expectEqual(activated, ["c"])
        row.mouseMoved(with: move)
        expectFalse(model.selecting)
        expectEqual(activated, ["c"])
    }

    func testSearchFilteringAndConfirmation() {
        expectTrue(WindowSearch.matches("edge 报告", title: "季度报告", applicationName: "Microsoft Edge"))
        expectTrue(WindowSearch.matches("CAFE", title: "Café notes", applicationName: "Notes"))
        expectTrue(WindowSearch.matches("abc", title: "ＡＢＣ", applicationName: "Editor"))
        expectFalse(WindowSearch.matches("edge missing", title: "季度报告", applicationName: "Microsoft Edge"))
        var activated: [String] = []
        let model = WindowModel(activateWindow: { activated.append($0.id) })
        model.entries = [entry("当前窗口"), entry("季度报告"), entry("会议记录")]
        model.recent = model.entries.map(\.id)
        model.beginSelection(sameApp: false, frontPID: getpid(), focusedID: "当前窗口", backwards: false)
        expectTrue(model.beginSearch())
        model.releaseCommand()
        expectTrue(model.selecting)
        expectTrue(activated.isEmpty)
        model.updateSearch("报告")
        expectEqual(model.choices.map(\.id), ["季度报告"])
        model.updateSearch("不存在")
        expectTrue(model.choices.isEmpty)
        model.moveSelection(backwards: false)
        model.updateSearch("  \n ")
        expectEqual(model.choices.map(\.id), ["当前窗口", "季度报告", "会议记录"])
        model.updateSearch(NSRunningApplication.current.localizedName ?? "")
        expectEqual(model.choices.count, 3)
        model.updateSearch("会议")
        model.finish()
        expectEqual(activated, ["会议记录"])
        expectFalse(model.searching)
        expectEqual(model.searchQuery, "")

        // Filtering respects the same-app gesture's frozen scope.
        model.entries.append(WindowEntry(id: "other", pid: getpid() + 1, app: .current,
            window: nil, title: "另一应用的报告"))
        model.beginSelection(sameApp: true, frontPID: getpid(), focusedID: "会议记录", backwards: false)
        model.beginSearch()
        model.updateSearch("报告")
        expectEqual(model.choices.map(\.id), ["季度报告"])
        model.finish(cancel: true)
        expectEqual(activated, ["会议记录"])
        model.beginSelection(sameApp: true, frontPID: getpid(), focusedID: "会议记录", backwards: false)
        expectFalse(model.searching)
        model.releaseCommand()
        expectEqual(activated.count, 2)
    }

    func testSearchKeyRoutingAndInputMethod() {
        _ = NSApplication.shared
        let controller = AppDelegate()
        let model = controller.model
        model.trusted = true
        model.entries = [entry("当前窗口"), entry("季度报告"), entry("会议记录")]
        let picker = NativeSwitcherView(frame: NSRect(x: 0, y: 0, width: 460, height: 240))
        let panel = controller.panel(width: 460, height: 240, searchable: true)
        expectTrue(panel.canBecomeKey)
        expectFalse(panel.canBecomeMain)
        panel.contentView = picker
        model.onSelectionChange = { picker.update(from: model) }
        func key(_ code: CGKeyCode, flags: CGEventFlags = []) -> CGEvent {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
            event.flags = flags
            return event
        }
        expectNotNil(controller.handle(type: .keyDown, event: key(3, flags: .maskCommand)))
        model.beginSelection(sameApp: true, frontPID: getpid(), focusedID: "当前窗口", backwards: false)
        expectNil(controller.handle(type: .keyDown, event: key(3, flags: .maskCommand)))
        expectTrue(model.searching)
        _ = controller.handle(type: .flagsChanged, event: key(55))
        expectTrue(model.selecting)
        // Input methods must receive Return, Escape and arrows before app commands.
        for code: CGKeyCode in [36, 53, 125, 126, 0] {
            expectNotNil(controller.handle(type: .keyDown, event: key(code)))
        }
        let field = picker.subviews.compactMap { $0 as? NSSearchField }.first!
        expectFalse(field.isHidden)
        let editor = NSTextView()
        editor.setMarkedText("bao", selectedRange: NSRange(location: 3, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        expectTrue(editor.hasMarkedText())
        let previous = model.selection
        for selector in [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.moveDown(_:)),
                         #selector(NSResponder.cancelOperation(_:))] {
            expectFalse(picker.control(field, textView: editor, doCommandBy: selector))
        }
        expectEqual(model.selection, previous)
        expectTrue(model.selecting)
        editor.unmarkText()
        expectTrue(picker.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        expectEqual(model.selection, (previous + 1) % 3)
        field.stringValue = "报告"
        picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        expectEqual(model.choices.map(\.id), ["季度报告"])
        field.stringValue = "no-match"
        picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        expectTrue(picker.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        expectTrue(model.selecting) // Enter on an empty result does not close or activate.
        expectTrue(picker.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        expectFalse(model.selecting)
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
checks.testRapidSwitchingUsesLiveFocusAndRecentOrder()
checks.testSameAppPickerCommitsOnlyOnRelease()
checks.testArrowRoutingPreservesAppShortcutsOutsidePicker()
checks.testHeldCommandRepaintsEverySelection()
checks.testPickerMouseConfirmsClickedRowOnlyOnce()
checks.testPickerHoverSelectsWithoutActivating()
checks.testSearchFilteringAndConfirmation()
checks.testSearchKeyRoutingAndInputMethod()
checks.testExitGracePeriodAndReentry()
checks.testMenuBarPreferencePersistsAndNotifies()
print("PASS: 13 regression checks (including search, IME key routing, picker repaints and mouse selection)")

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
