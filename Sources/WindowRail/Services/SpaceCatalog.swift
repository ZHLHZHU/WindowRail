import AppKit
import ApplicationServices
import Darwin

struct DesktopSpace: Identifiable {
    let id: UInt64
    let title: String
    let fullScreen: Bool
    var displayID: String = ""
}
struct SidebarGroup: Identifiable {
    let id: String
    let title: String
    let entries: [WindowEntry]
}

/// Optional, read-only SPI. Keep libraries loaded for the lifetime of their pointers.
/// No space mutation, Dock injection or SIP changes are used.
final class SpaceCatalog {
    typealias Connection = @convention(c) () -> Int32
    typealias CopyDisplays = @convention(c) (Int32) -> Unmanaged<CFArray>?
    typealias CopyMembership = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    typealias WindowNumber = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> Int32
    private let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private let ax = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY)
    private var connection: Connection?
    private var copyDisplays: CopyDisplays?
    private var copyMembership: CopyMembership?
    private var windowNumber: WindowNumber?
    private(set) var spaces: [DesktopSpace] = []

    init() {
        if let sky {
            if let p = dlsym(sky, "CGSMainConnectionID") { connection = unsafeBitCast(p, to: Connection.self) }
            if let p = dlsym(sky, "CGSCopyManagedDisplaySpaces") { copyDisplays = unsafeBitCast(p, to: CopyDisplays.self) }
            if let p = dlsym(sky, "CGSCopySpacesForWindows") { copyMembership = unsafeBitCast(p, to: CopyMembership.self) }
        }
        if let ax, let p = dlsym(ax, "_AXUIElementGetWindow") { windowNumber = unsafeBitCast(p, to: WindowNumber.self) }
    }
    func refresh() {
        guard let connection, let copyDisplays,
              let value = copyDisplays(connection())?.takeRetainedValue(),
              let displays = value as? [[String: Any]] else { spaces = []; return }
        var result: [DesktopSpace] = []
        var seen = Set<UInt64>()
        var desktop = 0
        for display in displays {
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard let number = (space["ManagedSpaceID"] ?? space["id64"]) as? NSNumber,
                      let type = space["type"] as? NSNumber else { continue }
                let id = number.uint64Value
                guard seen.insert(id).inserted else { continue }
                if type.intValue == 0 {
                    desktop += 1
                    result.append(DesktopSpace(id: id, title: L10n.format(.groupDesktop, desktop), fullScreen: false, displayID: display["Display Identifier"] as? String ?? ""))
                } else if type.intValue == 4 {
                    result.append(DesktopSpace(id: id, title: L10n.text(.groupFullscreen), fullScreen: true, displayID: display["Display Identifier"] as? String ?? ""))
                }
            }
        }
        spaces = result
    }
    func id(for window: AXUIElement) -> CGWindowID? {
        guard let windowNumber else { return nil }
        var id: CGWindowID = 0
        guard windowNumber(window, &id) == 0, id != 0 else { return nil }
        return id
    }
    func memberships(for id: CGWindowID?) -> [UInt64] {
        guard let id, let connection, let copyMembership,
              let result = copyMembership(connection(), 7, [NSNumber(value: id)] as CFArray)?.takeRetainedValue(),
              let numbers = result as? [NSNumber] else { return [] }
        return numbers.map(\.uint64Value)
    }
    func groups(for entries: [WindowEntry]) -> [SidebarGroup] {
        Self.group(entries, spaces: spaces)
    }
    static func group(_ entries: [WindowEntry], spaces: [DesktopSpace]) -> [SidebarGroup] {
        let fullScreenIDs = Set(spaces.filter(\.fullScreen).map(\.id))
        let desktops = spaces.filter { !$0.fullScreen }
        let desktopIDs = Set(desktops.map(\.id))
        let desktopSets = Dictionary(grouping: desktops, by: \.displayID).values.map { Set($0.map(\.id)) }
        func isFullScreen(_ entry: WindowEntry) -> Bool {
            let membership = Set(entry.spaceIDs)
            let onAllDesktops = desktopSets.contains { $0.count > 1 && $0.isSubset(of: membership) }
            return entry.fullScreen || !fullScreenIDs.isDisjoint(with: entry.spaceIDs) || onAllDesktops
        }
        // Contexts sidebar is alphabetical by app; its Command-Tab uses MRU separately.
        let sidebarEntries = entries.sorted {
            let order = ($0.app.localizedName ?? "").localizedStandardCompare($1.app.localizedName ?? "")
            return order == .orderedSame ? $0.id.localizedStandardCompare($1.id) == .orderedAscending : order == .orderedAscending
        }
        let windows = sidebarEntries.filter { $0.window != nil }
        var groups = [
            SidebarGroup(id: "apps", title: L10n.text(.groupApps), entries: sidebarEntries.filter { $0.window == nil }),
            SidebarGroup(id: "fullscreen", title: L10n.text(.groupFullscreen), entries: windows.filter(isFullScreen))
        ]
        for (index, desktop) in desktops.enumerated() {
            groups.append(SidebarGroup(id: "space:\(desktop.id)", title: L10n.format(.groupDesktop, index + 1),
                entries: windows.filter { !isFullScreen($0) && $0.spaceIDs.contains(desktop.id) }))
        }
        // Unknown membership is explicit; never guess Desktop 1 for an unmatched window.
        let unknown = windows.filter { !isFullScreen($0) && desktopIDs.isDisjoint(with: $0.spaceIDs) }
        if !unknown.isEmpty { groups.append(SidebarGroup(id: "unknown", title: L10n.text(.groupOther), entries: unknown)) }
        return groups
    }
}
