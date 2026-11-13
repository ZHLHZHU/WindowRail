import AppKit

/// Update the visible selection in the keyboard callback, without waiting for
/// SwiftUI's deferred rendering while an inactive panel consumes global keys.
final class NativeSwitcherView: NSView, NSSearchFieldDelegate {
    private let material = NSVisualEffectView()
    private let heading = NSTextField(labelWithString: "")
    private let help = NSTextField(labelWithString: "")
    private let scroll = NSScrollView()
    private let document = FlippedSwitcherDocument()
    private let searchField = SwitcherSearchField()
    private let emptyLabel = NSTextField(labelWithString: "")
    private weak var model: WindowModel?
    private var rows: [SwitcherRowView] = []
    private var ids: [String] = []
    private var origin: String?
    private var selectingWithMouse = false
    private(set) var selectedIndex: Int?
    var highlightedIndices: [Int] { rows.indices.filter { rows[$0].isSelected } }
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        addSubview(material)
        heading.font = .boldSystemFont(ofSize: 13)
        heading.textColor = .labelColor
        help.font = .systemFont(ofSize: 11)
        help.textColor = .secondaryLabelColor
        help.alignment = .right
        addSubview(heading)
        addSubview(help)
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.isHidden = true
        searchField.target = self
        searchField.action = #selector(searchChanged)
        addSubview(searchField)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        addSubview(emptyLabel)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(from model: WindowModel) {
        self.model = model
        heading.stringValue = L10n.text(.switcherTitle)
        help.stringValue = L10n.text(model.searching ? .switcherSearchHelp : .switcherHelp)
        searchField.placeholderString = L10n.text(.switcherSearchPlaceholder)
        searchField.setAccessibilityLabel(L10n.text(.switcherSearchPlaceholder))
        searchField.isHidden = !model.searching
        // Never replace the field editor's marked text during IME composition.
        if searchField.currentEditor() == nil && searchField.stringValue != model.searchQuery {
            searchField.stringValue = model.searchQuery
        }
        emptyLabel.stringValue = L10n.text(.switcherSearchEmpty)
        emptyLabel.isHidden = !model.searching || !model.choices.isEmpty
        let nextIDs = model.choices.map(\.id)
        if ids != nextIDs || origin != model.originWindowID {
            rows.forEach { $0.removeFromSuperview() }
            ids = nextIDs
            origin = model.originWindowID
            rows = model.choices.map { entry in
                SwitcherRowView(entry: entry, current: entry.id == origin, hover: { [weak self, weak model] in
                    guard let self, let model else { return }
                    self.selectingWithMouse = true
                    defer { self.selectingWithMouse = false }
                    model.selectChoice(id: entry.id)
                }) { [weak model] in
                    model?.confirmChoice(id: entry.id) ?? false
                }
            }
            rows.forEach { document.addSubview($0) }
            selectedIndex = nil
        }
        selectedIndex = rows.indices.contains(model.selection) ? model.selection : nil
        for index in rows.indices { rows[index].isSelected = index == selectedIndex }
        needsLayout = true
        layoutSubtreeIfNeeded()
        if !selectingWithMouse, let selectedIndex { document.scrollToVisible(rows[selectedIndex].frame) }
        // The panel is nonactivating: do not depend on a subsequent app event
        // to flush the highlight after the event tap consumes this key.
        displayIfNeeded()
    }

    override func layout() {
        super.layout()
        material.frame = bounds
        heading.frame = NSRect(x: 20, y: 18, width: 100, height: 18)
        help.frame = NSRect(x: 120, y: 19, width: max(0, bounds.width - 140), height: 16)
        searchField.frame = NSRect(x: 20, y: 44, width: max(0, bounds.width - 40), height: 26)
        let top: CGFloat = searchField.isHidden ? 44 : 82
        scroll.frame = NSRect(x: 10, y: top, width: max(0, bounds.width - 20), height: max(0, bounds.height - top - 10))
        emptyLabel.frame = NSRect(x: 20, y: top + 20, width: max(0, bounds.width - 40), height: 20)
        document.frame.size = NSSize(width: scroll.contentSize.width, height: CGFloat(rows.count) * 29)
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: 0, y: CGFloat(index) * 29, width: document.bounds.width, height: 26)
        }
    }

    func focusSearch() {
        guard model?.searching == true else { return }
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    func endSearchEditing() {
        window?.makeFirstResponder(nil)
        searchField.stringValue = ""
    }

    @objc private func searchChanged() {
        guard (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        model?.updateSearch(searchField.stringValue)
    }

    func controlTextDidChange(_ notification: Notification) { searchChanged() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let model, model.searching, !textView.hasMarkedText() else { return false }
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            model.moveSelection(backwards: true)
        case #selector(NSResponder.moveDown(_:)):
            model.moveSelection(backwards: false)
        case #selector(NSResponder.insertNewline(_:)):
            if !model.choices.isEmpty { model.finish() }
        case #selector(NSResponder.cancelOperation(_:)):
            model.finish(cancel: true)
        default:
            return false
        }
        return true
    }
}

/// Only search mode asks this nonactivating panel to take keyboard focus.
final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SwitcherSearchField: NSSearchField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let editor = currentEditor() as? NSTextView {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a": editor.selectAll(nil)
            case "c": editor.copy(nil)
            case "x": editor.cut(nil)
            case "v": editor.paste(nil)
            case "z": editor.undoManager?.undo()
            default: return super.performKeyEquivalent(with: event)
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class FlippedSwitcherDocument: NSView {
    override var isFlipped: Bool { true }
}

private final class SwitcherRowView: NSView {
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")
    private let current: Bool
    private let confirm: () -> Bool
    private let hover: () -> Void
    private var hoverTracking: NSTrackingArea?
    var isSelected = false {
        didSet {
            title.textColor = isSelected ? .white : .labelColor
            badge.textColor = isSelected ? .white : .secondaryLabelColor
            needsDisplay = true
        }
    }
    override var isFlipped: Bool { true }

    init(entry: WindowEntry, current: Bool, hover: @escaping () -> Void, confirm: @escaping () -> Bool) {
        self.current = current
        self.confirm = confirm
        self.hover = hover
        super.init(frame: .zero)
        icon.image = entry.app.icon
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.stringValue = entry.title
        title.font = .systemFont(ofSize: 14)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        badge.stringValue = current ? L10n.text(.windowCurrent) : ""
        badge.font = .systemFont(ofSize: 11, weight: .semibold)
        badge.alignment = .center
        addSubview(icon)
        addSubview(title)
        addSubview(badge)
        toolTip = entry.title
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
        setAccessibilityLabel(entry.title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func isAccessibilitySelected() -> Bool { isSelected }
    override func accessibilityPerformPress() -> Bool { confirm() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Icons, text and the current-window badge share the row's click target.
        super.hitTest(point) == nil ? nil : self
    }
    override func mouseDown(with event: NSEvent) {
        // Confirm on press, before releasing Command can commit the keyboard selection.
        _ = confirm()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTracking = area
    }
    override func mouseMoved(with event: NSEvent) { hover() }

    override func layout() {
        super.layout()
        let badgeWidth = current ? badge.intrinsicContentSize.width + 12 : 0
        icon.frame = NSRect(x: 7, y: 3, width: 20, height: 20)
        let titleHeight = title.intrinsicContentSize.height
        title.frame = NSRect(x: 32, y: (bounds.height - titleHeight) / 2,
                             width: max(0, bounds.width - 39 - badgeWidth), height: titleHeight)
        let badgeHeight = badge.intrinsicContentSize.height
        badge.frame = NSRect(x: bounds.width - badgeWidth - 7, y: (bounds.height - badgeHeight) / 2,
                             width: badgeWidth, height: badgeHeight)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isSelected {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        }
        if current {
            (isSelected ? NSColor.white : NSColor.labelColor).withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: badge.frame.insetBy(dx: 0, dy: -2), xRadius: 5, yRadius: 5).fill()
        }
    }
}
