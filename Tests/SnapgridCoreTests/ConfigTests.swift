import XCTest
@testable import SnapgridCore

final class TOMLTests: XCTestCase {
    func testParsesTablesArraysAndScalars() throws {
        let doc = try TOMLParser.parse("""
        # comment
        [settings]
        grid = "6x4"   # trailing comment
        gap = 8
        ratio = 0.5
        on = true

        [[shortcut]]
        name = "has # hash and \\"quotes\\""
        [[shortcut]]
        name = "second"
        """)
        XCTAssertEqual(doc.tables["settings"]?["grid"], .string("6x4"))
        XCTAssertEqual(doc.tables["settings"]?["gap"], .integer(8))
        XCTAssertEqual(doc.tables["settings"]?["ratio"], .float(0.5))
        XCTAssertEqual(doc.tables["settings"]?["on"], .bool(true))
        XCTAssertEqual(doc.arrays["shortcut"]?.count, 2)
        XCTAssertEqual(doc.arrays["shortcut"]?[0]["name"], .string("has # hash and \"quotes\""))
        XCTAssertEqual(doc.arrayLines["shortcut"], [8, 10])
    }

    func testReportsLineNumbers() {
        XCTAssertThrowsError(try TOMLParser.parse("[settings]\ngrid = \"6x4\ngap = 1")) { error in
            XCTAssertEqual((error as? TOMLError)?.line, 2)
        }
        XCTAssertThrowsError(try TOMLParser.parse("[a]\nx = 1\nx = 2")) { error in
            XCTAssertEqual((error as? TOMLError)?.line, 3)
        }
        XCTAssertThrowsError(try TOMLParser.parse("x = [1, 2]"))
    }

    func testQuoteRoundTrips() throws {
        let tricky = "a \"b\" \\ c\td"
        let doc = try TOMLParser.parse("v = \(TOMLParser.quote(tricky))")
        XCTAssertEqual(doc.root["v"], .string(tricky))
    }
}

final class KeyComboTests: XCTestCase {
    func testParsesModifiersAndKeys() throws {
        let combo = try KeyCombo.parse("Ctrl+Option+Left")
        XCTAssertEqual(combo.modifiers, [.control, .option])
        XCTAssertEqual(combo.key, .code(123))
        XCTAssertEqual(try KeyCombo.parse("cmd+shift+k").key, .character("k"))
        XCTAssertEqual(try KeyCombo.parse("keycode:37").key, .code(37))
        XCTAssertEqual(try KeyCombo.parse("alt+plus").key, .code(24))
        XCTAssertEqual(combo.description, "ctrl+alt+left")
    }

    func testRejectsBadCombos() {
        XCTAssertThrowsError(try KeyCombo.parse("ctrl+"))
        XCTAssertThrowsError(try KeyCombo.parse("hyper+a"))
        XCTAssertThrowsError(try KeyCombo.parse("ctrl+nosuchkey"))
        XCTAssertThrowsError(try KeyCombo.parse("keycode:999"))
    }

    func testCarbonAndCocoaFlags() {
        XCTAssertEqual(Modifiers([.command, .control]).carbonFlags, 256 | 4096)
        XCTAssertEqual(Modifiers(cocoaFlags: (1 << 18) | (1 << 19)), [.control, .option])
    }
}

final class ConfigTests: XCTestCase {
    func testDefaultConfigIsValid() throws {
        let config = try Config.parse(DefaultConfig.text)
        XCTAssertEqual(config.settings.grid, GridSize(columns: 6, rows: 6))
        XCTAssertEqual(config.settings.leader, try KeyCombo.parse("ctrl+alt+space"))
        XCTAssertTrue(config.shortcuts.contains { $0.action == .nextScreen })
        XCTAssertTrue(config.shortcuts.contains { !$0.global })
        XCTAssertTrue(config.warnings.isEmpty)
    }

    func testExampleFileMatchesDefault() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("config.example.toml")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), DefaultConfig.text)
    }

    func testShortcutGridOverride() throws {
        let config = try Config.parse("""
        [[shortcut]]
        keys = "ctrl+alt+e"
        grid = "3x1"
        cells = "0,0 2x1"
        """)
        XCTAssertEqual(config.shortcuts[0].action, .place(CellRange(x: 0, y: 0, w: 2, h: 1), grid: GridSize(columns: 3, rows: 1)))
        XCTAssertEqual(config.shortcuts[0].name, "ctrl+alt+e")
    }

    func testValidationErrors() {
        func assertError(_ text: String, contains needle: String, line: Int? = nil,
                         file: StaticString = #filePath, lineNo: UInt = #line) {
            XCTAssertThrowsError(try Config.parse(text), file: file, line: lineNo) { error in
                let e = error as? ConfigError
                XCTAssertTrue(e?.message.contains(needle) == true, "\(error)", file: file, line: lineNo)
                if let line { XCTAssertEqual(e?.line, line, file: file, line: lineNo) }
            }
        }
        assertError("[[shortcut]]\nkeys = \"ctrl+a\"\ncells = \"5,0 2x1\"", contains: "do not fit", line: 1)
        assertError("[[shortcut]]\nkeys = \"a\"\ncells = \"0,0 1x1\"", contains: "no modifier")
        assertError("[[shortcut]]\nkeys = \"ctrl+a\"\ncells = \"0,0 1x1\"\n[[shortcut]]\nkeys = \"ctrl+a\"\ncells = \"0,0 1x1\"",
                    contains: "already used", line: 4)
        assertError("[[shortcut]]\nkeys = \"ctrl+a\"\ncels = \"0,0 1x1\"", contains: "unknown key 'cels'")
        assertError("[[shortcut]]\nkeys = \"ctrl+a\"\naction = \"next-screen\"\ncells = \"0,0 1x1\"", contains: "only apply")
        assertError("[setings]\ngap = 1", contains: "unknown table")
        assertError("[settings]\ngrid = \"0x4\"", contains: "grid must look like")
        assertError("[settings]\nleader = \"ctrl+alt+space\"\n[[shortcut]]\nkeys = \"ctrl+alt+space\"\ncells = \"0,0 1x1\"",
                    contains: "leader key")
    }

    func testLocalWithoutLeaderWarns() throws {
        let config = try Config.parse("[[shortcut]]\nkeys = \"l\"\ncells = \"0,0 1x1\"\nglobal = false")
        XCTAssertEqual(config.warnings.count, 1)
    }

    func testBareFunctionKeyMayBeGlobal() throws {
        XCTAssertNoThrow(try Config.parse("[[shortcut]]\nkeys = \"f13\"\ncells = \"0,0 1x1\""))
    }
}
