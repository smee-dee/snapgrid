import Foundation

/// One Divvy shortcut as stored in its preferences (an NSKeyedArchiver array of `Shortcut` objects).
public struct DivvyShortcut: Equatable {
    public var name: String
    public var enabled: Bool
    public var global: Bool
    public var keyCode: Int
    public var cocoaFlags: Int
    public var startColumn: Int, startRow: Int, endColumn: Int, endRow: Int
    public var columns: Int, rows: Int
    public var subdivided: Bool

    public init(name: String, enabled: Bool = true, global: Bool, keyCode: Int, cocoaFlags: Int,
                startColumn: Int, startRow: Int, endColumn: Int, endRow: Int,
                columns: Int, rows: Int, subdivided: Bool = false) {
        self.name = name; self.enabled = enabled; self.global = global
        self.keyCode = keyCode; self.cocoaFlags = cocoaFlags
        self.startColumn = startColumn; self.startRow = startRow
        self.endColumn = endColumn; self.endRow = endRow
        self.columns = columns; self.rows = rows; self.subdivided = subdivided
    }
}

final class DivvyShortcutRecord: NSObject, NSCoding {
    let value: DivvyShortcut

    init(_ value: DivvyShortcut) { self.value = value }

    required init?(coder: NSCoder) {
        let name = (coder.decodeObject(forKey: "nameKey") as? String) ?? ""
        value = DivvyShortcut(
            name: name,
            enabled: coder.containsValue(forKey: "enabled") ? coder.decodeBool(forKey: "enabled") : true,
            global: coder.decodeBool(forKey: "global"),
            keyCode: coder.decodeInteger(forKey: "keyComboCode"),
            cocoaFlags: coder.decodeInteger(forKey: "keyComboFlags"),
            startColumn: coder.decodeInteger(forKey: "selectionStartColumn"),
            startRow: coder.decodeInteger(forKey: "selectionStartRow"),
            endColumn: coder.decodeInteger(forKey: "selectionEndColumn"),
            endRow: coder.decodeInteger(forKey: "selectionEndRow"),
            columns: coder.decodeInteger(forKey: "sizeColumns"),
            rows: coder.decodeInteger(forKey: "sizeRows"),
            subdivided: coder.decodeBool(forKey: "subdivided"))
    }

    func encode(with coder: NSCoder) {
        coder.encode(value.name as NSString, forKey: "nameKey")
        coder.encode(value.enabled, forKey: "enabled")
        coder.encode(value.global, forKey: "global")
        coder.encode(value.keyCode, forKey: "keyComboCode")
        coder.encode(value.cocoaFlags, forKey: "keyComboFlags")
        coder.encode(value.startColumn, forKey: "selectionStartColumn")
        coder.encode(value.startRow, forKey: "selectionStartRow")
        coder.encode(value.endColumn, forKey: "selectionEndColumn")
        coder.encode(value.endRow, forKey: "selectionEndRow")
        coder.encode(value.columns, forKey: "sizeColumns")
        coder.encode(value.rows, forKey: "sizeRows")
        coder.encode(value.subdivided, forKey: "subdivided")
    }
}

public struct DivvyImportError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

public enum DivvyImporter {
    /// Preference domains used by the direct-download and Mac App Store builds.
    public static let domains = ["com.mizage.direct.Divvy", "com.mizage.Divvy"]

    public struct Preferences {
        public var shortcuts: [DivvyShortcut]
        /// Other top-level preference keys (names only; values may include the licence key).
        public var otherKeys: [String]
    }

    /// Reads a Divvy preferences plist (binary or XML, e.g. from `defaults export com.mizage.direct.Divvy -`).
    public static func readPreferences(_ data: Data) throws -> Preferences {
        let plist: Any
        do { plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) }
        catch { throw DivvyImportError(message: "not a property list: \(error.localizedDescription)") }
        guard let dict = plist as? [String: Any] else {
            throw DivvyImportError(message: "unexpected plist layout (top level is not a dictionary)")
        }
        guard let archive = dict["shortcuts"] as? Data else {
            throw DivvyImportError(message: "no 'shortcuts' entry found — is this Divvy's preference file?")
        }
        let others = dict.keys.filter { $0 != "shortcuts" }.sorted()
        return Preferences(shortcuts: try decodeShortcuts(archive), otherKeys: others)
    }

    public static func decodeShortcuts(_ archive: Data) throws -> [DivvyShortcut] {
        let unarchiver: NSKeyedUnarchiver
        do { unarchiver = try NSKeyedUnarchiver(forReadingFrom: archive) }
        catch { throw DivvyImportError(message: "cannot read shortcut archive: \(error.localizedDescription)") }
        unarchiver.requiresSecureCoding = false
        unarchiver.setClass(DivvyShortcutRecord.self, forClassName: "Shortcut")
        let root = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
        unarchiver.finishDecoding()
        guard let array = root as? [Any] else {
            throw DivvyImportError(message: "shortcut archive does not contain a list")
        }
        return array.compactMap { ($0 as? DivvyShortcutRecord)?.value }
    }

    /// Builds an archive in Divvy's format (used by tests and for round-trip checks).
    public static func encodeShortcuts(_ shortcuts: [DivvyShortcut]) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName("Shortcut", for: DivvyShortcutRecord.self)
        archiver.encode(shortcuts.map(DivvyShortcutRecord.init) as NSArray, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    public struct Converted {
        public var cells: CellRange
        public var grid: GridSize
        public var combo: String
        public var note: String?
    }

    public static func convert(_ s: DivvyShortcut, layoutCharacter: ((UInt32) -> Character?)? = nil) -> Converted {
        let x0 = min(s.startColumn, s.endColumn), x1 = max(s.startColumn, s.endColumn)
        let y0 = min(s.startRow, s.endRow), y1 = max(s.startRow, s.endRow)
        var grid = GridSize(columns: max(s.columns, 1), rows: max(s.rows, 1))
        var note: String?
        if x1 >= grid.columns || y1 >= grid.rows {
            grid = GridSize(columns: grid.columns * 2, rows: grid.rows * 2)
            note = "Divvy subdivided grid; selection mapped onto \(grid) — double-check placement"
        } else if s.subdivided {
            note = "Divvy marked this grid as subdivided — double-check placement"
        }
        let cells = CellRange(x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1)
        let key = KeyCodes.portableName(for: UInt32(max(s.keyCode, 0)), layoutCharacter: layoutCharacter)
        let combo = (Modifiers(cocoaFlags: s.cocoaFlags).names + [key]).joined(separator: "+")
        return Converted(cells: cells, grid: grid, combo: combo, note: note)
    }

    /// Renders a GridKeys config from Divvy shortcuts.
    public static func renderConfig(_ prefs: Preferences, source: String,
                                    layoutCharacter: ((UInt32) -> Character?)? = nil) -> String {
        let converted = prefs.shortcuts.map { ($0, convert($0, layoutCharacter: layoutCharacter)) }

        var counts: [String: Int] = [:]
        for (_, c) in converted { counts[c.grid.description, default: 0] += 1 }
        let defaultGrid = counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? "6x6"
        let hasLocal = prefs.shortcuts.contains { !$0.global && $0.enabled }

        var out = """
        # GridKeys config — imported from Divvy (\(source))
        # See README.md ("Config reference") for all options.
        #
        # cells = "col,row WxH": 0-based top-left cell, then width x height in cells.

        [settings]
        grid = \(TOMLParser.quote(defaultGrid))
        gap = 0

        """
        if hasLocal {
            out += """

            # Divvy "local" shortcuts only worked while the Divvy panel was open.
            # Here they work for \(Int(Settings().leaderTimeout))s after pressing the leader key.
            # Set it to the hotkey you used to open the Divvy panel.
            leader = "ctrl+alt+space"
            leader_timeout = \(Int(Settings().leaderTimeout))

            """
        }
        if !prefs.otherKeys.isEmpty {
            out += "\n# Other Divvy settings found (not imported): \(prefs.otherKeys.joined(separator: ", "))\n"
        }

        var seen: [String: String] = [:]
        for (s, c) in converted {
            var comments: [String] = []
            var disabled = false
            if !s.enabled { comments.append("disabled in Divvy"); disabled = true }
            if let note = c.note { comments.append(note) }
            let hasModifiers = !Modifiers(cocoaFlags: s.cocoaFlags).isEmpty
            if s.global, !hasModifiers {
                comments.append("global without modifiers is not allowed; made local")
            }
            let global = s.global && hasModifiers
            let id = "\(global ? "g" : "l"):\(c.combo)"
            if !disabled, let other = seen[id] {
                comments.append("same keys as '\(other)'"); disabled = true
            }
            if !disabled { seen[id] = s.name }

            let prefix = disabled ? "# " : ""
            out += "\n"
            for comment in comments { out += "# NOTE: \(comment)\n" }
            let name = s.name.isEmpty ? c.combo : s.name
            out += "\(prefix)[[shortcut]]\n"
            out += "\(prefix)name = \(TOMLParser.quote(name))\n"
            out += "\(prefix)keys = \(TOMLParser.quote(c.combo))\n"
            out += "\(prefix)cells = \(TOMLParser.quote(c.cells.description))\n"
            if c.grid.description != defaultGrid {
                out += "\(prefix)grid = \(TOMLParser.quote(c.grid.description))\n"
            }
            if !global { out += "\(prefix)global = false\n" }
        }
        if prefs.shortcuts.isEmpty { out += "\n# Divvy had no shortcuts configured.\n" }
        return out
    }
}
