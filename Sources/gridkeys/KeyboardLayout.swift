#if os(macOS)
import Carbon
import GridKeysCore

/// Maps between characters and virtual key codes using the active keyboard layout,
/// so shortcuts follow the key labels (e.g. QWERTZ) rather than US positions.
enum KeyboardLayout {
    /// Characters produced by key codes 0–127 on the current layout (without modifiers).
    static func characterTable() -> [UInt32: Character] {
        guard let data = layoutData() else { return [:] }
        return data.withUnsafeBytes { raw -> [UInt32: Character] in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return [:] }
            var table: [UInt32: Character] = [:]
            for code in UInt32(0)..<128 {
                var deadKeyState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                            &deadKeyState, chars.count, &length, &chars)
                guard status == noErr, length > 0 else { continue }
                let s = String(utf16CodeUnits: chars, count: length)
                if s.count == 1, let ch = s.first, !ch.isWhitespace, !ch.isNewline { table[code] = ch }
            }
            return table
        }
    }

    private static func layoutData() -> Data? {
        for copy in [TISCopyCurrentKeyboardLayoutInputSource, TISCopyCurrentASCIICapableKeyboardLayoutInputSource] {
            guard let source = copy()?.takeRetainedValue(),
                  let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { continue }
            return Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        }
        return nil
    }

    static func character(for keyCode: UInt32) -> Character? {
        characterTable()[keyCode]
    }

    static func resolve(_ key: Key, table: [UInt32: Character]) -> UInt32? {
        switch key {
        case .code(let c):
            return c
        case .character(let ch):
            let wanted = String(ch).lowercased()
            // Lowest code first, so main-block keys win over their keypad duplicates.
            if let code = table.filter({ String($0.value).lowercased() == wanted }).keys.min() { return code }
            return KeyCodes.ansiCharacters[Character(wanted)]
        }
    }
}
#endif
