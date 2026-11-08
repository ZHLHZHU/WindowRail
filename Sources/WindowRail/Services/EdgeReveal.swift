import Foundation

/// Small dwell at the edge prevents accidental reveals; a longer exit delay
/// lets the pointer cross the border without making the panel flicker.
struct EdgeReveal {
    private(set) var visible = false
    private var enteredEdgeAt: TimeInterval?
    private var leftPanelAt: TimeInterval?

    mutating func setVisible(_ value: Bool) {
        visible = value
        enteredEdgeAt = nil
        leftPanelAt = nil
    }

    mutating func update(nearEdge: Bool, insidePanel: Bool, now: TimeInterval) -> Bool {
        if visible {
            enteredEdgeAt = nil
            if insidePanel || nearEdge {
                leftPanelAt = nil
            } else {
                if leftPanelAt == nil { leftPanelAt = now }
                if now - (leftPanelAt ?? now) >= 0.25 { setVisible(false) }
            }
        } else {
            leftPanelAt = nil
            if nearEdge {
                if enteredEdgeAt == nil { enteredEdgeAt = now }
                if now - (enteredEdgeAt ?? now) >= 0.10 { setVisible(true) }
            } else {
                enteredEdgeAt = nil
            }
        }
        return visible
    }
}
