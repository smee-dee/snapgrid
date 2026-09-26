import Foundation

public struct Modifiers: OptionSet, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)

    /// Carbon `RegisterEventHotKey` modifier mask (cmdKey, shiftKey, optionKey, controlKey).
    public var carbonFlags: UInt32 {
        var f: UInt32 = 0
        if contains(.command) { f |= 1 << 8 }
        if contains(.shift) { f |= 1 << 9 }
        if contains(.option) { f |= 1 << 11 }
        if contains(.control) { f |= 1 << 12 }
        return f
    }

    /// Cocoa `NSEvent.ModifierFlags` raw values, as stored in Divvy's `keyComboFlags`.
    public init(cocoaFlags: Int) {
        var m: Modifiers = []
        if cocoaFlags & (1 << 17) != 0 { m.insert(.shift) }
        if cocoaFlags & (1 << 18) != 0 { m.insert(.control) }
        if cocoaFlags & (1 << 19) != 0 { m.insert(.option) }
        if cocoaFlags & (1 << 20) != 0 { m.insert(.command) }
        self = m
    }

    public var names: [String] {
        var out: [String] = []
        if contains(.control) { out.append("ctrl") }
        if contains(.option) { out.append("alt") }
        if contains(.shift) { out.append("shift") }
        if contains(.command) { out.append("cmd") }
        return out
    }
}

/// The key part of a combo. Named keys (arrows, F-keys, …) have fixed key codes;
/// single characters are resolved against the active keyboard layout at runtime,
/// so "z" means the key labelled Z even on a German (QWERTZ) keyboard.
public enum Key: Hashable {
    case code(UInt32)
    case character(Character)
}

public struct KeyCombo: Hashable, CustomStringConvertible {
    public var modifiers: Modifiers
    public var key: Key

    public init(modifiers: Modifiers, key: Key) {
        self.modifiers = modifiers
        self.key = key
    }

    public var description: String {
        let keyName: String
        switch key {
        case .code(let c): keyName = KeyCodes.name(for: c) ?? "keycode:\(c)"
        case .character(let ch): keyName = String(ch)
        }
        return (modifiers.names + [keyName]).joined(separator: "+")
    }

    public struct ParseError: Error, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    /// Parses strings like "ctrl+alt+left", "cmd+shift+k", "keycode:37", "alt+plus".
    public static func parse(_ text: String) throws -> KeyCombo {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, !last.isEmpty, !parts.dropLast().contains("") else {
            throw ParseError(message: "invalid key combo '\(text)' (use e.g. \"ctrl+alt+left\"; write \"plus\" for the + key)")
        }
        var mods: Modifiers = []
        for part in parts.dropLast() {
            switch part {
            case "ctrl", "control", "⌃": mods.insert(.control)
            case "alt", "opt", "option", "⌥": mods.insert(.option)
            case "shift", "⇧": mods.insert(.shift)
            case "cmd", "command", "⌘": mods.insert(.command)
            default: throw ParseError(message: "unknown modifier '\(part)' in '\(text)'")
            }
        }
        return KeyCombo(modifiers: mods, key: try parseKey(last, in: text))
    }

    private static func parseKey(_ name: String, in text: String) throws -> Key {
        if name.hasPrefix("keycode:") {
            guard let code = UInt32(name.dropFirst("keycode:".count)), code < 128 else {
                throw ParseError(message: "invalid raw keycode in '\(text)'")
            }
            return .code(code)
        }
        if let code = KeyCodes.named[name] { return .code(code) }
        if name.count == 1, let ch = name.first { return .character(ch) }
        throw ParseError(message: "unknown key '\(name)' in '\(text)'")
    }
}

/// macOS virtual key codes (kVK_*). Character keys use ANSI (US) positions and are
/// only a fallback when the active layout can't be queried.
public enum KeyCodes {
    public static let named: [String: UInt32] = [
        "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53, "forwarddelete": 117, "help": 114,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111, "f13": 105, "f14": 107, "f15": 113,
        "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
        "plus": 24, "minus": 27, "equal": 24, "comma": 43, "period": 47, "slash": 44,
        "backslash": 42, "semicolon": 41, "quote": 39, "grave": 50,
        "leftbracket": 33, "rightbracket": 30,
        "pad0": 82, "pad1": 83, "pad2": 84, "pad3": 85, "pad4": 86, "pad5": 87, "pad6": 88,
        "pad7": 89, "pad8": 91, "pad9": 92, "paddecimal": 65, "padmultiply": 67, "padplus": 69,
        "paddivide": 75, "padminus": 78, "padequal": 81, "padenter": 76, "padclear": 71,
    ]

    public static let ansiCharacters: [Character: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
        "`": 50,
    ]

    private static let preferredNames: [UInt32: String] = {
        var out: [UInt32: String] = [:]
        let order = ["return", "tab", "space", "delete", "escape", "forwarddelete", "help",
                     "home", "end", "pageup", "pagedown", "left", "right", "down", "up"]
            + (1...20).map { "f\($0)" }
            + ["pad0", "pad1", "pad2", "pad3", "pad4", "pad5", "pad6", "pad7", "pad8", "pad9",
               "paddecimal", "padmultiply", "padplus", "paddivide", "padminus", "padequal",
               "padenter", "padclear"]
        for name in order { if let c = named[name], out[c] == nil { out[c] = name } }
        return out
    }()

    public static func name(for code: UInt32) -> String? {
        if let n = preferredNames[code] { return n }
        if let ch = ansiCharacters.first(where: { $0.value == code })?.key { return String(ch) }
        return nil
    }

    /// Name for a key code that stays correct in any layout: named keys by name,
    /// everything else as a raw code unless the caller supplies a layout lookup.
    public static func portableName(for code: UInt32, layoutCharacter: ((UInt32) -> Character?)? = nil) -> String {
        if let n = preferredNames[code] { return n }
        if let ch = layoutCharacter?(code), ch != "+", !ch.isWhitespace { return String(ch).lowercased() }
        return "keycode:\(code)"
    }
}
