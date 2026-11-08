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

expectEqual(L10n.text("settings.open", language: "en"), "Settings…")
expectEqual(L10n.text("settings.open", language: "zh-Hans"), "设置…")
expectEqual(L10n.text("settings.open", language: "fr"), "Settings…")
expectEqual(L10n.text("window.current", language: "en"), "Current")
print("PASS: English, Simplified Chinese and unsupported-language fallback")
