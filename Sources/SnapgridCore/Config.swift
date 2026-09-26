import Foundation

public struct GridSize: Equatable, CustomStringConvertible {
    public var columns: Int
    public var rows: Int
    public init(columns: Int, rows: Int) { self.columns = columns; self.rows = rows }
    public var description: String { "\(columns)x\(rows)" }

    /// Parses "6x4" (columns x rows).
    public static func parse(_ s: String) -> GridSize? {
        let parts = s.lowercased().split(separator: "x").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let c = Int(parts[0]), let r = Int(parts[1]),
              (1...100).contains(c), (1...100).contains(r) else { return nil }
        return GridSize(columns: c, rows: r)
    }
}

/// A rectangular selection of grid cells: origin column/row (0-based) plus width/height in cells.
public struct CellRange: Equatable, CustomStringConvertible {
    public var x: Int, y: Int, w: Int, h: Int
    public init(x: Int, y: Int, w: Int, h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }
    public var description: String { "\(x),\(y) \(w)x\(h)" }

    /// Parses "0,0 3x4" → column 0, row 0, 3 columns wide, 4 rows tall.
    public static func parse(_ s: String) -> CellRange? {
        let halves = s.split(separator: " ", omittingEmptySubsequences: true)
        guard halves.count == 2 else { return nil }
        let origin = halves[0].split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard origin.count == 2, let x = origin[0], let y = origin[1],
              let size = GridSize.parse(String(halves[1])) else { return nil }
        return CellRange(x: x, y: y, w: size.columns, h: size.rows)
    }

    public func fits(in grid: GridSize) -> Bool {
        x >= 0 && y >= 0 && w >= 1 && h >= 1 && x + w <= grid.columns && y + h <= grid.rows
    }
}

public enum Action: Equatable {
    case place(CellRange, grid: GridSize)
    case nextScreen
    case previousScreen
}

public struct Shortcut: Equatable {
    public var name: String
    public var combo: KeyCombo
    public var action: Action
    /// Global shortcuts work anywhere; local ones only right after pressing the leader key
    /// (the equivalent of Divvy's local shortcuts, which work while its panel is open).
    public var global: Bool

    public init(name: String, combo: KeyCombo, action: Action, global: Bool) {
        self.name = name; self.combo = combo; self.action = action; self.global = global
    }
}

public struct Settings: Equatable {
    public var grid = GridSize(columns: 6, rows: 6)
    public var gap: Double = 0
    public var leader: KeyCombo?
    public var leaderTimeout: Double = 3

    public init() {}
}

public struct ConfigError: Error, CustomStringConvertible {
    public let line: Int?
    public let message: String
    public var description: String { line.map { "line \($0): \(message)" } ?? message }
}

public struct Config: Equatable {
    public var settings = Settings()
    public var shortcuts: [Shortcut] = []
    public var warnings: [String] = []

    public init(settings: Settings = Settings(), shortcuts: [Shortcut] = []) {
        self.settings = settings; self.shortcuts = shortcuts
    }

    public static var defaultPath: URL {
        let env = ProcessInfo.processInfo.environment
        let base = env["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        return base.appendingPathComponent("snapgrid/config.toml")
    }

    public static func load(from url: URL) throws -> Config {
        let text: String
        do { text = try String(contentsOf: url, encoding: .utf8) }
        catch { throw ConfigError(line: nil, message: "cannot read \(url.path): \(error.localizedDescription)") }
        return try parse(text)
    }

    public static func parse(_ text: String) throws -> Config {
        let doc: TOMLDocument
        do { doc = try TOMLParser.parse(text) }
        catch let e as TOMLError { throw ConfigError(line: e.line, message: e.message) }

        let known: Set<String> = ["settings"]
        for name in doc.tables.keys where !known.contains(name) {
            throw ConfigError(line: nil, message: "unknown table [\(name)]")
        }
        for name in doc.arrays.keys where name != "shortcut" {
            throw ConfigError(line: nil, message: "unknown table [[\(name)]] (did you mean [[shortcut]]?)")
        }
        if !doc.root.isEmpty {
            throw ConfigError(line: nil, message: "keys must live under [settings] or [[shortcut]]")
        }

        var config = Config()
        let s = doc.tables["settings"] ?? [:]
        try checkKeys(s, allowed: ["grid", "gap", "leader", "leader_timeout"], context: "[settings]", line: nil)
        if let v = s["grid"] {
            guard let str = v.stringValue, let g = GridSize.parse(str) else {
                throw ConfigError(line: nil, message: "[settings] grid must look like \"6x4\"")
            }
            config.settings.grid = g
        }
        if let v = s["gap"] {
            guard let d = v.doubleValue, d >= 0, d <= 200 else {
                throw ConfigError(line: nil, message: "[settings] gap must be a number of points between 0 and 200")
            }
            config.settings.gap = d
        }
        if let v = s["leader"] {
            guard let str = v.stringValue else { throw ConfigError(line: nil, message: "[settings] leader must be a string") }
            do { config.settings.leader = try KeyCombo.parse(str) }
            catch { throw ConfigError(line: nil, message: "[settings] leader: \(error)") }
        }
        if let v = s["leader_timeout"] {
            guard let d = v.doubleValue, d > 0, d <= 60 else {
                throw ConfigError(line: nil, message: "[settings] leader_timeout must be seconds between 0 and 60")
            }
            config.settings.leaderTimeout = d
        }

        let entries = doc.arrays["shortcut"] ?? []
        let lines = doc.arrayLines["shortcut"] ?? []
        var seen: [String: String] = [:]
        for (i, entry) in entries.enumerated() {
            let line = lines[i]
            let shortcut = try parseShortcut(entry, line: line, settings: config.settings)
            let scope = shortcut.global ? "global" : "local"
            let id = "\(scope):\(shortcut.combo)"
            if let other = seen[id] {
                throw ConfigError(line: line, message: "'\(shortcut.name)' uses \(shortcut.combo), already used by '\(other)'")
            }
            if let leader = config.settings.leader, shortcut.global, shortcut.combo == leader {
                throw ConfigError(line: line, message: "'\(shortcut.name)' uses the leader key \(leader)")
            }
            seen[id] = shortcut.name
            config.shortcuts.append(shortcut)
        }

        if config.settings.leader == nil, config.shortcuts.contains(where: { !$0.global }) {
            config.warnings.append("local shortcuts (global = false) are ignored because [settings] leader is not set")
        }
        return config
    }

    private static func checkKeys(_ table: TOMLTable, allowed: Set<String>, context: String, line: Int?) throws {
        for key in table.keys.sorted() where !allowed.contains(key) {
            throw ConfigError(line: line, message: "unknown key '\(key)' in \(context)")
        }
    }

    private static func parseShortcut(_ t: TOMLTable, line: Int, settings: Settings) throws -> Shortcut {
        try checkKeys(t, allowed: ["name", "keys", "cells", "grid", "action", "global"], context: "[[shortcut]]", line: line)
        guard let keys = t["keys"]?.stringValue else {
            throw ConfigError(line: line, message: "[[shortcut]] needs keys = \"…\"")
        }
        let combo: KeyCombo
        do { combo = try KeyCombo.parse(keys) }
        catch { throw ConfigError(line: line, message: "\(error)") }

        let global = t["global"]?.boolValue ?? true
        if t["global"] != nil, t["global"]?.boolValue == nil {
            throw ConfigError(line: line, message: "global must be true or false")
        }
        if global, combo.modifiers.isEmpty, !isFunctionKey(combo.key) {
            throw ConfigError(line: line, message: "global shortcut \(combo) has no modifier and would swallow that key everywhere; add a modifier or set global = false")
        }

        let action: Action
        switch t["action"]?.stringValue ?? "place" {
        case "place":
            guard let cellStr = t["cells"]?.stringValue, let cells = CellRange.parse(cellStr) else {
                throw ConfigError(line: line, message: "[[shortcut]] needs cells = \"col,row WxH\", e.g. \"0,0 3x6\"")
            }
            var grid = settings.grid
            if let g = t["grid"] {
                guard let str = g.stringValue, let parsed = GridSize.parse(str) else {
                    throw ConfigError(line: line, message: "grid must look like \"6x4\"")
                }
                grid = parsed
            }
            guard cells.fits(in: grid) else {
                throw ConfigError(line: line, message: "cells \(cells) do not fit in a \(grid) grid")
            }
            action = .place(cells, grid: grid)
        case "next-screen": action = .nextScreen
        case "previous-screen": action = .previousScreen
        case let other:
            throw ConfigError(line: line, message: "unknown action '\(other)' (use place, next-screen or previous-screen)")
        }
        if case .place = action {
        } else if t["cells"] != nil || t["grid"] != nil {
            throw ConfigError(line: line, message: "cells/grid only apply to action = \"place\"")
        }

        let name = t["name"]?.stringValue ?? combo.description
        return Shortcut(name: name, combo: combo, action: action, global: global)
    }

    private static func isFunctionKey(_ key: Key) -> Bool {
        guard case .code(let c) = key, let name = KeyCodes.name(for: c) else { return false }
        return name.hasPrefix("f") && Int(name.dropFirst()) != nil
    }
}

extension Config {
    /// TOML text that `Config.parse` reads back to the same settings and shortcuts.
    /// Comments from a hand-edited file are not preserved.
    public func render() -> String {
        func number(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }
        let q = TOMLParser.quote
        var out = """
        # Snapgrid config — saved by Snapgrid Settings.
        # See README.md ("Config reference") for all options.
        #
        # cells = "col,row WxH": 0-based top-left cell, then width x height in cells.

        [settings]
        grid = \(q(settings.grid.description))
        gap = \(number(settings.gap))

        """
        if let leader = settings.leader {
            out += "leader = \(q(leader.description))\n"
            out += "leader_timeout = \(number(settings.leaderTimeout))\n"
        }
        for s in shortcuts {
            out += "\n[[shortcut]]\n"
            out += "name = \(q(s.name))\n"
            out += "keys = \(q(s.combo.description))\n"
            switch s.action {
            case .place(let cells, let grid):
                out += "cells = \(q(cells.description))\n"
                if grid != settings.grid { out += "grid = \(q(grid.description))\n" }
            case .nextScreen: out += "action = \"next-screen\"\n"
            case .previousScreen: out += "action = \"previous-screen\"\n"
            }
            if !s.global { out += "global = false\n" }
        }
        return out
    }
}
