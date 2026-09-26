#if os(macOS)
import AppKit
import SnapgridCore
import SwiftUI

/// Editable copy of one shortcut. `combo` is nil until a key has been recorded.
struct ShortcutDraft: Identifiable, Equatable {
    enum Kind: CaseIterable, Identifiable {
        case place, nextScreen, previousScreen
        var id: Self { self }
        var title: String {
            switch self {
            case .place: return "Place on grid"
            case .nextScreen: return "Move to next display"
            case .previousScreen: return "Move to previous display"
            }
        }
    }

    var id = UUID()
    var name: String
    var combo: KeyCombo?
    var global: Bool
    var kind: Kind = .place
    var cells: CellRange
    /// nil: use the default grid from General.
    var grid: GridSize?

    init(name: String, combo: KeyCombo?, global: Bool, cells: CellRange) {
        self.name = name; self.combo = combo; self.global = global; self.cells = cells
    }

    init(_ s: Shortcut, defaultGrid: GridSize) {
        name = s.name; combo = s.combo; global = s.global
        cells = CellRange(x: 0, y: 0, w: defaultGrid.columns, h: defaultGrid.rows)
        switch s.action {
        case .place(let c, let g): cells = c; grid = g == defaultGrid ? nil : g
        case .nextScreen: kind = .nextScreen
        case .previousScreen: kind = .previousScreen
        }
    }
}

enum RecordTarget: Equatable {
    case leader
    case shortcut(UUID)
}

@MainActor
final class SettingsModel: ObservableObject {
    struct Problem { var shortcut: UUID?; var message: String }
    struct Check { var config: Config?; var problem: Problem?; var warnings: [String] = [] }

    @Published var grid = GridSize(columns: 6, rows: 6)
    @Published var gap: Double = 0
    @Published var margin: Insets?
    @Published var leader: KeyCombo?
    @Published var leaderTimeout: Double = 3
    @Published var showGrid = true
    @Published var shortcuts: [ShortcutDraft] = []
    @Published var selection: UUID?
    @Published private(set) var recording: RecordTarget?
    @Published private(set) var fileError: String?
    @Published private(set) var accessibilityGranted = Accessibility.isGranted
    @Published var notRegistered: [String] = []
    @Published var alert: String?

    let configURL: URL
    var onSave: () -> Void = {}
    var pauseHotKeys: (Bool) -> Void = { _ in }
    var onLoginChanged: () -> Void = {}
    var onLocationChanged: () -> Void = {}
    private var savedText = ""
    private var monitor: Any?

    init(configURL: URL) {
        self.configURL = configURL
        revert()
    }

    // MARK: Loading and saving

    func load(_ config: Config) {
        grid = config.settings.grid
        gap = config.settings.gap
        margin = config.settings.margin
        leader = config.settings.leader
        leaderTimeout = config.settings.leaderTimeout
        showGrid = config.settings.showGrid
        shortcuts = config.shortcuts.map { ShortcutDraft($0, defaultGrid: config.settings.grid) }
        if !shortcuts.contains(where: { $0.id == selection }) { selection = shortcuts.first?.id }
    }

    /// Discards unsaved edits and reads the config file again.
    func revert() {
        stopRecording()
        do {
            let text = try String(contentsOf: configURL, encoding: .utf8)
            load(try Config.parse(text))
            savedText = check.config?.render() ?? ""
            fileError = nil
        } catch {
            if shortcuts.isEmpty { load(Config()) }
            savedText = ""
            fileError = (error as? ConfigError)?.description ?? error.localizedDescription
        }
    }

    /// The drafted config, validated by the same parser the app uses.
    var check: Check {
        var config = Config()
        config.settings.grid = grid
        config.settings.gap = gap
        config.settings.margin = margin
        config.settings.leader = leader
        config.settings.leaderTimeout = leaderTimeout
        config.settings.showGrid = showGrid
        for d in shortcuts {
            guard let combo = d.combo else {
                return Check(problem: Problem(shortcut: d.id, message: "“\(d.name)” has no keys yet. Click Record Shortcut."))
            }
            let action: Action
            switch d.kind {
            case .place: action = .place(d.cells, grid: d.grid ?? grid)
            case .nextScreen: action = .nextScreen
            case .previousScreen: action = .previousScreen
            }
            let name = d.name.trimmingCharacters(in: .whitespaces)
            config.shortcuts.append(Shortcut(name: name.isEmpty ? combo.description : name,
                                             combo: combo, action: action, global: d.global))
        }
        let text = config.render()
        do {
            let parsed = try Config.parse(text)
            return Check(config: config, warnings: parsed.warnings)
        } catch let error as ConfigError {
            // Map the error's line back to the shortcut it belongs to.
            var id: UUID?
            if let line = error.line, let i = Config.shortcutIndex(forErrorLine: line, in: text), i < shortcuts.count {
                id = shortcuts[i].id
            }
            return Check(problem: Problem(shortcut: id, message: error.message))
        } catch {
            return Check(problem: Problem(shortcut: nil, message: "\(error)"))
        }
    }

    var isDirty: Bool { check.config?.render() != savedText }

    func save() {
        stopRecording()
        guard let config = check.config else { return }
        let text = config.render()
        do {
            try CLI.write(text, to: configURL, force: true)
            savedText = text
            fileError = nil
            onSave()
        } catch {
            alert = "Could not save \(configURL.path): \((error as? CLI.Failure)?.message ?? error.localizedDescription)"
        }
    }

    func importDivvy() {
        do {
            let (data, source) = try CLI.readInstalledDivvyPreferences()
            let prefs = try DivvyImporter.readPreferences(data)
            let table = KeyboardLayout.characterTable()
            load(try Config.parse(DivvyImporter.renderConfig(prefs, source: source, layoutCharacter: { table[$0] })))
            alert = "Imported \(shortcuts.count) shortcuts from Divvy. Review them, then click Save (or Revert to undo)."
        } catch {
            alert = "Divvy import failed: \((error as? CLI.Failure)?.message ?? "\(error)")"
        }
    }

    // MARK: Editing shortcuts

    func binding(for id: UUID) -> Binding<ShortcutDraft> {
        let fallback = shortcuts.first { $0.id == id } ?? ShortcutDraft(name: "", combo: nil, global: true, cells: CellRange(x: 0, y: 0, w: 1, h: 1))
        return Binding(
            get: { self.shortcuts.first { $0.id == id } ?? fallback },
            set: { value in
                if let i = self.shortcuts.firstIndex(where: { $0.id == id }) { self.shortcuts[i] = value }
            })
    }

    func addShortcut() {
        let draft = ShortcutDraft(name: "New Shortcut", combo: nil, global: leader == nil,
                                  cells: CellRange(x: 0, y: 0, w: max(grid.columns / 2, 1), h: grid.rows))
        shortcuts.append(draft)
        selection = draft.id
        record(.shortcut(draft.id))
    }

    func duplicateSelected() {
        guard let i = shortcuts.firstIndex(where: { $0.id == selection }) else { return }
        var copy = shortcuts[i]
        copy.id = UUID()
        copy.name += " copy"
        copy.combo = nil
        shortcuts.insert(copy, at: i + 1)
        selection = copy.id
    }

    func removeSelected() {
        guard let i = shortcuts.firstIndex(where: { $0.id == selection }) else { return }
        shortcuts.remove(at: i)
        selection = shortcuts.isEmpty ? nil : shortcuts[min(i, shortcuts.count - 1)].id
    }

    // MARK: Recording keys

    /// Carbon hotkeys fire before the window sees the key, so they're paused while recording.
    func record(_ target: RecordTarget) {
        stopRecording()
        recording = target
        pauseHotKeys(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.recordKey(event) ?? false }
            return consumed ? nil : event
        }
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording != nil {
            recording = nil
            pauseHotKeys(false)
        }
    }

    private func recordKey(_ event: NSEvent) -> Bool {
        guard let target = recording else { return false }
        var mods: Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.command) { mods.insert(.command) }
        if event.keyCode == 53, mods.isEmpty {
            stopRecording()
            return true
        }
        let table = KeyboardLayout.characterTable()
        let key = KeyCodes.portableName(for: UInt32(event.keyCode), layoutCharacter: { table[$0] })
        guard let combo = try? KeyCombo.parse((mods.names + [key]).joined(separator: "+")) else {
            NSSound.beep()
            return true
        }
        switch target {
        case .leader: leader = combo
        case .shortcut(let id):
            if let i = shortcuts.firstIndex(where: { $0.id == id }) { shortcuts[i].combo = combo }
        }
        stopRecording()
        return true
    }

    // MARK: App status

    var canLaunchAtLogin: Bool { LoginItem.isAvailable }

    var launchAtLogin: Bool {
        get { LoginItem.isEnabled }
        set {
            objectWillChange.send()
            do { try LoginItem.set(newValue) } catch { alert = "Launch at login: \(error.localizedDescription)" }
            onLoginChanged()
        }
    }

    func refreshStatus() {
        let granted = Accessibility.isGranted
        if granted != accessibilityGranted { accessibilityGranted = granted }
    }

    func openAccessibilitySettings() { Accessibility.request() }

    // MARK: iCloud Drive

    let cloud = CloudSync.iCloudDrive
    /// Set when turning sync on finds different settings from another Mac in iCloud Drive.
    @Published var cloudChoicePending = false

    var iCloudSync: Bool {
        get { cloud.isEnabled(for: configURL) }
        set {
            objectWillChange.send()
            if newValue, cloud.hasCloudConfig,
               (try? String(contentsOf: cloud.configURL, encoding: .utf8)) != (try? String(contentsOf: configURL, encoding: .utf8)) {
                cloudChoicePending = true
                return
            }
            do {
                if newValue { try cloud.enable(for: configURL, useCloudCopy: false) } else { try cloud.disable(for: configURL) }
                onLocationChanged()
            } catch {
                alert = "iCloud Drive sync: \(error.localizedDescription)"
            }
        }
    }

    func enableCloudSync(useCloudCopy: Bool) {
        objectWillChange.send()
        do {
            try cloud.enable(for: configURL, useCloudCopy: useCloudCopy)
            onLocationChanged()
            if useCloudCopy { revert() }
        } catch {
            alert = "iCloud Drive sync: \(error.localizedDescription)"
        }
    }

    var configLocation: String {
        iCloudSync ? "iCloud Drive › Snapgrid › config.toml"
            : (configURL.path as NSString).abbreviatingWithTildeInPath
    }
}
#endif
