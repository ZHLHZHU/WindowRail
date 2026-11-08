import AppKit
import SwiftUI
import ApplicationServices

struct WindowEntry: Identifiable {
    let id: String
    let pid: pid_t
    let app: NSRunningApplication
    let window: AXUIElement?
    let title: String
    var fullScreen: Bool = false
    var spaceIDs: [UInt64] = []
}
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
    return result
}
