import AppKit
import Combine

private final class TopDownView: NSView {
    override var isFlipped: Bool { true }
}
/// The button handles clicks; separate native views handle icon and label layout.
private final class EmptyRailCell: NSButtonCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {}
}
private final class RailButton: NSButton {
    var actionBlock: (() -> Void)?
    private let label = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private var tracking: NSTrackingArea?
    private var hovered = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { true }
    override var image: NSImage? {
        didSet {
            iconView.image = image
            iconView.isHidden = image == nil
            needsLayout = true
        }
    }
    init(title: String, action: @escaping () -> Void) {
        super.init(frame: .zero)
        cell = EmptyRailCell(textCell: title)
        self.title = title
        actionBlock = action
        isBordered = false
        setButtonType(.momentaryChange)
        target = self
        self.action = #selector(performAction)
        wantsLayer = true
        label.stringValue = title
        label.font = .systemFont(ofSize: 14)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.wraps = false
        label.cell?.isScrollable = false
        label.setAccessibilityElement(false)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.isHidden = true
        iconView.setAccessibilityElement(false)
        addSubview(iconView)
        addSubview(label)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }
    override func layout() {
        super.layout()
        iconView.frame = NSRect(x: 0, y: (bounds.height - 20) / 2, width: 20, height: 20)
        let leading: CGFloat = image == nil ? 0 : 24
        let labelHeight = ceil(label.cell?.cellSize.height ?? 17)
        label.frame = NSRect(x: leading, y: floor((bounds.height - labelHeight) / 2),
                             width: max(0, bounds.width - leading), height: labelHeight)
    }
    func setTitleStyle(font: NSFont, color: NSColor) {
        label.font = font
        label.textColor = color
        needsLayout = true
    }
    @objc private func performAction() { actionBlock?() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    private func updateHoverColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (hovered ? NSColor.labelColor.withAlphaComponent(0.08) : NSColor.clear).cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateHoverColor()
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; updateHoverColor() }
    override func mouseExited(with event: NSEvent) { hovered = false; updateHoverColor() }
}

/// Explicit row frames keep long AX titles from changing the sidebar's layout.
final class NativeRailView: NSView {
    private let scroll = NSScrollView()
    private let document = TopDownView()
    private let model: WindowModel
    private let settings: () -> Void
    private var subscription: AnyCancellable?
    private var signature = ""
    private(set) var preferredHeight: CGFloat = 14
    var onContentChanged: (() -> Void)?

    init(model: WindowModel, settings: @escaping () -> Void) {
        self.model = model
        self.settings = settings
        super.init(frame: NSRect(x: 0, y: 0, width: 174, height: 400))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 0.5
        updateThemeColors()
        layer?.masksToBounds = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.documentView = document
        addSubview(scroll)
        subscription = model.$groups.combineLatest(model.$trusted)
            .receive(on: RunLoop.main)
            .sink { [weak self] groups, trusted in self?.render(groups: groups, trusted: trusted) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    private func updateThemeColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateThemeColors()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateThemeColors()
    }
    override func layout() {
        super.layout()
        scroll.frame = bounds
        document.setFrameSize(NSSize(width: bounds.width, height: preferredHeight))
    }
    private func render(groups: [SidebarGroup], trusted: Bool) {
        let groupSignatures: [String] = groups.map { group in
            let entrySignatures = group.entries.map { "\($0.id):\($0.title)" }
            return "\(group.id):\(group.title):" + entrySignatures.joined(separator: "\u{1f}")
        }
        let next = "\(L10n.currentLanguage):\(trusted):" + groupSignatures.joined(separator: "\u{1e}")
        guard signature != next else { return }
        signature = next
        let oldOffset = scroll.contentView.bounds.origin.y
        document.subviews.forEach { $0.removeFromSuperview() }
        var y: CGFloat = 0
        for group in groups {
            let header = NSTextField(labelWithString: group.title)
            header.font = .systemFont(ofSize: 12, weight: .semibold)
            header.textColor = .secondaryLabelColor
            let headerHeight = ceil(header.cell?.cellSize.height ?? 15)
            header.frame = NSRect(x: 8, y: y + floor((28 - headerHeight) / 2), width: 158, height: headerHeight)
            document.addSubview(header)
            y += 28
                for entry in group.entries {
                    let button = RailButton(title: entry.title) { [weak model] in model?.activate(entry) }
                    button.frame = NSRect(x: 5, y: y, width: 164, height: 26)
                    if let icon = entry.app.icon?.copy() as? NSImage {
                        icon.size = NSSize(width: 20, height: 20)
                        button.image = icon
                        button.imagePosition = .imageLeading
                        button.imageScaling = .scaleProportionallyDown
                        button.imageHugsTitle = true
                    }
                    button.toolTip = entry.title
                    button.setAccessibilityLabel(entry.title)
                    document.addSubview(button)
                    y += 26
                }
            y += 7
        }
        if !trusted {
            let permission = RailButton(title: L10n.text(.accessibilityEnable), action: settings)
            permission.setTitleStyle(font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
            permission.frame = NSRect(x: 10, y: y, width: 154, height: 34)
            document.addSubview(permission)
            y += 34
        }
        preferredHeight = max(14, y + 7)
        document.frame = NSRect(x: 0, y: 0, width: 174, height: preferredHeight)
        needsLayout = true
        layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(oldOffset, max(0, preferredHeight - bounds.height))))
        scroll.reflectScrolledClipView(scroll.contentView)
        onContentChanged?()
    }
}
