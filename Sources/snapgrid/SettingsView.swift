#if os(macOS)
import AppKit
import SnapgridCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                ShortcutsTab(model: model).tabItem { Text("Shortcuts") }
                GeneralTab(model: model).tabItem { Text("General") }
            }
            .padding([.horizontal, .top], 12)
            FooterBar(model: model)
        }
        .frame(minWidth: 780, minHeight: 560)
        .alert("Snapgrid", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alert ?? "")
        }
    }
}

private struct FooterBar: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let check = model.check
        let dirty = model.isDirty
        HStack(spacing: 12) {
            if let problem = check.problem {
                Label(problem.message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                if let id = problem.shortcut, id != model.selection {
                    Button("Show") { model.selection = id }
                }
            } else if let error = model.fileError {
                Label("config.toml has an error (\(error)). Saving replaces it.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if let warning = check.warnings.first {
                Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            } else {
                Text(dirty ? "Unsaved changes" : "Saved. Changes apply as soon as you save.").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Revert") { model.revert() }.disabled(!dirty)
            Button("Save") { model.save() }
                .keyboardShortcut("s")
                .disabled(check.config == nil || !dirty)
        }
        .lineLimit(2)
        .padding(12)
    }
}

// MARK: Shortcuts

private struct ShortcutsTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let problemID = model.check.problem?.shortcut
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $model.selection) {
                    ForEach(model.shortcuts) { draft in
                        ShortcutRow(draft: draft, grid: draft.grid ?? model.grid,
                                    hasProblem: draft.id == problemID,
                                    notRegistered: draft.combo.map { c in model.notRegistered.contains { $0.hasPrefix("\(c) ") } } ?? false)
                    }
                    .onMove { model.shortcuts.move(fromOffsets: $0, toOffset: $1) }
                }
                Divider()
                HStack(spacing: 4) {
                    Button { model.addShortcut() } label: { Image(systemName: "plus") }
                        .help("Add a shortcut")
                    Button { model.removeSelected() } label: { Image(systemName: "minus") }
                        .help("Delete the selected shortcut")
                        .disabled(model.selection == nil)
                    Button { model.duplicateSelected() } label: { Image(systemName: "plus.square.on.square") }
                        .help("Duplicate the selected shortcut")
                        .disabled(model.selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(width: 270)
            Divider()
            if let id = model.selection, model.shortcuts.contains(where: { $0.id == id }) {
                ShortcutEditor(model: model, id: id)
            } else {
                Text("Select a shortcut, or add one with +.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct ShortcutRow: View {
    let draft: ShortcutDraft
    let grid: GridSize
    let hasProblem: Bool
    let notRegistered: Bool

    var body: some View {
        HStack(spacing: 10) {
            ActionThumbnail(kind: draft.kind, cells: draft.cells, grid: grid)
                .frame(width: 40, height: 25)
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.name.isEmpty ? "Untitled" : draft.name).lineLimit(1)
                Text(keysText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if hasProblem || (draft.kind == .place && !draft.cells.fits(in: grid)) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            } else if notRegistered {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help("Another app already uses this shortcut")
            }
        }
        .padding(.vertical, 2)
    }

    private var keysText: String {
        guard let combo = draft.combo else { return "No keys" }
        return draft.global ? combo.symbols : "Leader, then \(combo.symbols)"
    }
}

private struct ShortcutEditor: View {
    @ObservedObject var model: SettingsModel
    let id: UUID

    var body: some View {
        let draft = model.binding(for: id)
        let grid = draft.wrappedValue.grid ?? model.grid
        Form {
            Section {
                TextField("Name", text: draft.name)
                LabeledContent("Keys") {
                    KeyRecorder(model: model, target: .shortcut(id), combo: draft.wrappedValue.combo)
                }
                Picker("Works", selection: draft.global) {
                    Text("Anywhere").tag(true)
                    Text("After the leader key").tag(false)
                }
                Picker("Action", selection: draft.kind) {
                    ForEach(ShortcutDraft.Kind.allCases) { Text($0.title).tag($0) }
                }
            }
            if draft.wrappedValue.kind == .place {
                Section {
                    Toggle("Own grid size", isOn: Binding(
                        get: { draft.wrappedValue.grid != nil },
                        set: { draft.wrappedValue.grid = $0 ? model.grid : nil }))
                    if draft.wrappedValue.grid != nil {
                        GridSizeFields(grid: Binding(get: { grid }, set: { draft.wrappedValue.grid = $0 }))
                    }
                    GridPicker(grid: grid, cells: draft.cells)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } header: {
                    Text("Position")
                } footer: {
                    let c = draft.wrappedValue.cells
                    Text("Drag across the grid to choose where the window goes: column \(c.x + 1), row \(c.y + 1), \(c.w) × \(c.h) of \(grid.columns) × \(grid.rows) cells.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Text("Moves the focused window to the \(draft.wrappedValue.kind == .nextScreen ? "next" : "previous") display and keeps its relative size and position.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct GridSizeFields: View {
    @Binding var grid: GridSize

    var body: some View {
        Stepper("Columns: \(grid.columns)", value: $grid.columns, in: 1...100)
        Stepper("Rows: \(grid.rows)", value: $grid.rows, in: 1...100)
    }
}

// MARK: Grid drawing

private let screenAspect: CGFloat = {
    guard let frame = NSScreen.main?.visibleFrame, frame.height > 0 else { return 16.0 / 10.0 }
    return frame.width / frame.height
}()

private func drawGrid(_ ctx: GraphicsContext, size: CGSize, grid: GridSize, cells: CellRange, lines: Bool) {
    let cw = size.width / CGFloat(grid.columns), ch = size.height / CGFloat(grid.rows)
    ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: lines ? 6 : 3),
             with: .color(Color.secondary.opacity(0.15)))
    if lines {
        var path = Path()
        for c in 1..<grid.columns {
            path.move(to: CGPoint(x: CGFloat(c) * cw, y: 0))
            path.addLine(to: CGPoint(x: CGFloat(c) * cw, y: size.height))
        }
        for r in 1..<grid.rows {
            path.move(to: CGPoint(x: 0, y: CGFloat(r) * ch))
            path.addLine(to: CGPoint(x: size.width, y: CGFloat(r) * ch))
        }
        ctx.stroke(path, with: .color(Color.secondary.opacity(0.35)), lineWidth: 0.5)
    }
    let rect = CGRect(x: CGFloat(cells.x) * cw, y: CGFloat(cells.y) * ch,
                      width: CGFloat(cells.w) * cw, height: CGFloat(cells.h) * ch)
        .intersection(CGRect(origin: .zero, size: size))
        .insetBy(dx: lines ? 1.5 : 1, dy: lines ? 1.5 : 1)
    guard !rect.isNull, rect.width > 0, rect.height > 0 else { return }
    let selection = Path(roundedRect: rect, cornerRadius: lines ? 4 : 2)
    ctx.fill(selection, with: .color(Color.accentColor.opacity(0.5)))
    if lines { ctx.stroke(selection, with: .color(Color.accentColor), lineWidth: 1.5) }
}

/// Divvy-style picker: drag across cells to select the window's area.
private struct GridPicker: View {
    let grid: GridSize
    @Binding var cells: CellRange

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in drawGrid(ctx, size: size, grid: grid, cells: cells, lines: true) }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    func cell(_ p: CGPoint) -> (Int, Int) {
                        let x = Int(p.x / geo.size.width * CGFloat(grid.columns))
                        let y = Int(p.y / geo.size.height * CGFloat(grid.rows))
                        return (min(max(x, 0), grid.columns - 1), min(max(y, 0), grid.rows - 1))
                    }
                    let a = cell(value.startLocation), b = cell(value.location)
                    cells = CellRange(x: min(a.0, b.0), y: min(a.1, b.1), w: abs(a.0 - b.0) + 1, h: abs(a.1 - b.1) + 1)
                })
        }
        .aspectRatio(screenAspect, contentMode: .fit)
    }
}

private struct ActionThumbnail: View {
    let kind: ShortcutDraft.Kind
    let cells: CellRange
    let grid: GridSize

    var body: some View {
        switch kind {
        case .place:
            Canvas { ctx, size in drawGrid(ctx, size: size, grid: grid, cells: cells, lines: false) }
        case .nextScreen:
            Image(systemName: "arrow.right.square").font(.title2).foregroundStyle(.secondary)
        case .previousScreen:
            Image(systemName: "arrow.left.square").font(.title2).foregroundStyle(.secondary)
        }
    }
}

// MARK: Keys

private struct KeyRecorder: View {
    @ObservedObject var model: SettingsModel
    let target: RecordTarget
    let combo: KeyCombo?

    var body: some View {
        let active = model.recording == target
        Button {
            if active { model.stopRecording() } else { model.record(target) }
        } label: {
            Text(active ? "Type the shortcut… (Esc cancels)" : combo?.symbols ?? "Record Shortcut")
                .frame(minWidth: 170)
        }
        .help("Click, then press the key combination")
    }
}

// MARK: General

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Grid") {
                GridSizeFields(grid: $model.grid)
                LabeledContent("Gap between windows") {
                    HStack {
                        Slider(value: $model.gap, in: 0...40, step: 1)
                        Text("\(Int(model.gap)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }
            Section {
                LabeledContent("Leader key") {
                    HStack {
                        KeyRecorder(model: model, target: .leader, combo: model.leader)
                        if model.leader != nil {
                            Button { model.leader = nil } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless)
                                .help("Remove the leader key")
                        }
                    }
                }
                LabeledContent("Active for") {
                    HStack {
                        Slider(value: $model.leaderTimeout, in: 1...10, step: 0.5)
                        Text(String(format: "%.1f s", model.leaderTimeout)).monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                Text("Leader key")
            } footer: {
                Text("Shortcuts set to “After the leader key” work for this long after you press it, like the shortcuts in Divvy's panel. Esc cancels.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("App") {
                if model.canLaunchAtLogin {
                    Toggle("Launch at login", isOn: $model.launchAtLogin)
                }
                LabeledContent("Accessibility") {
                    if model.accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant Access…") { model.openAccessibilitySettings() }
                    }
                }
                if !model.notRegistered.isEmpty {
                    LabeledContent("Not registered") {
                        VStack(alignment: .trailing) {
                            ForEach(model.notRegistered, id: \.self) { Text($0) }
                        }
                    }
                }
            }
            Section {
                Toggle("Sync settings with iCloud Drive", isOn: $model.iCloudSync)
                    .disabled(!model.cloud.isAvailable)
            } header: {
                Text("Sync")
            } footer: {
                Text(model.cloud.isAvailable
                     ? "Keeps config.toml in iCloud Drive › Snapgrid so your other Macs use the same shortcuts. Launch at login stays per Mac."
                     : "Turn on iCloud Drive in System Settings › Apple Account › iCloud to sync.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Config file") {
                LabeledContent("Location") {
                    Text(model.configLocation).textSelection(.enabled)
                }
                HStack {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.configURL.resolvingSymlinksInPath()])
                    }
                    Button("Open in Editor") { NSWorkspace.shared.open(model.configURL.resolvingSymlinksInPath()) }
                    Spacer()
                    Button("Import from Divvy…") { model.importDivvy() }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("iCloud Drive already has Snapgrid settings", isPresented: $model.cloudChoicePending) {
            Button("Use the Settings from iCloud") { model.enableCloudSync(useCloudCopy: true) }
            Button("Replace Them with This Mac's") { model.enableCloudSync(useCloudCopy: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Another Mac saved different shortcuts there. Whichever you don't choose is kept as config.toml.bak.")
        }
        .task {
            while !Task.isCancelled {
                model.refreshStatus()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
}
#endif
