#if os(macOS)
import AppKit
import SnapgridCore

/// Divvy's panel: a translucent grid over the focused window's display. Drag across cells
/// and release to place the window there. The panel never becomes key, so the app whose
/// window is being placed stays frontmost and focused.
@MainActor
final class GridOverlay {
    private var panel: NSPanel?
    private var clickMonitor: Any?

    var isVisible: Bool { panel != nil }

    func show(grid: GridSize, on screen: NSScreen, app: NSRunningApplication?,
              onSelect: @escaping (CellRange) -> Void, onSettings: @escaping () -> Void,
              onDismiss: @escaping () -> Void) {
        hide()
        let visible = screen.visibleFrame
        let padding: CGFloat = 16, titleHeight: CGFloat = 28, hintHeight: CGFloat = 16
        let gridWidth: CGFloat = 400
        let gridHeight = (gridWidth / max(visible.width / visible.height, 0.5)).rounded()
        let size = NSSize(width: gridWidth + 2 * padding,
                          height: padding + titleHeight + 10 + gridHeight + 10 + hintHeight + padding - 4)

        let panel = OverlayPanel(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.appearance = NSAppearance(named: .darkAqua)

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true

        var y = size.height - padding - titleHeight
        let icon = NSImageView(frame: NSRect(x: padding, y: y + 2, width: 24, height: 24))
        icon.image = app?.icon
        let title = NSTextField(labelWithString: app?.localizedName ?? "Snapgrid")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .labelColor
        title.frame = NSRect(x: padding + 32, y: y + 4, width: gridWidth - 64, height: 20)
        let settings = ActionButton(symbol: "gearshape.fill", label: "Snapgrid Settings", action: onSettings)
        settings.frame = NSRect(x: padding + gridWidth - 24, y: y + 2, width: 24, height: 24)

        y -= 10 + gridHeight
        let gridView = GridSelectView(grid: grid, onSelect: onSelect)
        gridView.frame = NSRect(x: padding, y: y, width: gridWidth, height: gridHeight)

        let hint = NSTextField(labelWithString: "Drag across the grid and release to place the window. Esc closes.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        hint.frame = NSRect(x: padding, y: y - 10 - hintHeight, width: gridWidth, height: hintHeight)

        for view in [icon, title, settings, gridView, hint] as [NSView] { background.addSubview(view) }
        panel.contentView = background
        panel.setFrameOrigin(NSPoint(x: (visible.midX - size.width / 2).rounded(),
                                     y: (visible.midY - size.height / 2).rounded()))
        panel.orderFrontRegardless()
        self.panel = panel

        // Clicks in other apps close the panel, like Divvy's.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated { onDismiss() }
        }
    }

    func hide() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Borderless symbol button that reacts to the first click, since the panel is never key.
private final class ActionButton: NSButton {
    private let handler: () -> Void

    init(symbol: String, label: String, action: @escaping () -> Void) {
        handler = action
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        isBordered = false
        imagePosition = .imageOnly
        contentTintColor = .secondaryLabelColor
        toolTip = label
        target = self
        self.action = #selector(clicked)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func clicked() { handler() }
}

private final class GridSelectView: NSView {
    let grid: GridSize
    let onSelect: (CellRange) -> Void
    private var start: (x: Int, y: Int)?
    private var selection: CellRange?
    private var hover: (x: Int, y: Int)?

    init(grid: GridSize, onSelect: @escaping (CellRange) -> Void) {
        self.grid = grid
        self.onSelect = onSelect
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func cell(_ event: NSEvent) -> (x: Int, y: Int) {
        let p = convert(event.locationInWindow, from: nil)
        let x = Int(p.x / bounds.width * CGFloat(grid.columns))
        let y = Int(p.y / bounds.height * CGFloat(grid.rows))
        return (min(max(x, 0), grid.columns - 1), min(max(y, 0), grid.rows - 1))
    }

    private func range(_ a: (x: Int, y: Int), _ b: (x: Int, y: Int)) -> CellRange {
        CellRange(x: min(a.x, b.x), y: min(a.y, b.y), w: abs(a.x - b.x) + 1, h: abs(a.y - b.y) + 1)
    }

    override func mouseDown(with event: NSEvent) {
        let c = cell(event)
        start = c
        selection = range(c, c)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        selection = range(start, cell(event))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        let picked = range(start, cell(event))
        self.start = nil
        onSelect(picked)
    }

    override func mouseMoved(with event: NSEvent) {
        hover = cell(event)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hover = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let spacing: CGFloat = 3
        let cw = bounds.width / CGFloat(grid.columns), ch = bounds.height / CGFloat(grid.rows)
        let active = selection ?? hover.map { range($0, $0) }
        for row in 0..<grid.rows {
            for col in 0..<grid.columns {
                let rect = NSRect(x: CGFloat(col) * cw + spacing / 2, y: CGFloat(row) * ch + spacing / 2,
                                  width: cw - spacing, height: ch - spacing)
                let on = active.map { col >= $0.x && col < $0.x + $0.w && row >= $0.y && row < $0.y + $0.h } ?? false
                (on ? NSColor.controlAccentColor.withAlphaComponent(selection == nil ? 0.5 : 0.9)
                    : NSColor.white.withAlphaComponent(0.1)).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            }
        }
    }
}
#endif
