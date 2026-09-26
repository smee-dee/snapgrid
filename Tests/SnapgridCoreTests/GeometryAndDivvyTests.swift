import XCTest
@testable import SnapgridCore

final class GeometryTests: XCTestCase {
    let screen = Rect(x: 0, y: 25, width: 1200, height: 600)

    func testFrameWithoutGap() {
        let left = Geometry.frame(for: CellRange(x: 0, y: 0, w: 3, h: 6), grid: GridSize(columns: 6, rows: 6), in: screen)
        XCTAssertEqual(left, Rect(x: 0, y: 25, width: 600, height: 600))
        let cell = Geometry.frame(for: CellRange(x: 5, y: 5, w: 1, h: 1), grid: GridSize(columns: 6, rows: 6), in: screen)
        XCTAssertEqual(cell, Rect(x: 1000, y: 525, width: 200, height: 100))
    }

    func testGapIsUniformBetweenWindowsAndEdges() {
        let grid = GridSize(columns: 2, rows: 1)
        let l = Geometry.frame(for: CellRange(x: 0, y: 0, w: 1, h: 1), grid: grid, in: screen, gap: 10)
        let r = Geometry.frame(for: CellRange(x: 1, y: 0, w: 1, h: 1), grid: grid, in: screen, gap: 10)
        XCTAssertEqual(l.x - screen.x, 10)
        XCTAssertEqual(r.x - l.maxX, 10)
        XCTAssertEqual(screen.maxX - r.maxX, 10)
        XCTAssertEqual(l.y - screen.y, 10)
        XCTAssertEqual(screen.maxY - l.maxY, 10)
    }

    func testScreenIndexAndMove() {
        let a = Rect(x: 0, y: 0, width: 1000, height: 800)
        let b = Rect(x: 1000, y: 0, width: 2000, height: 1000)
        let win = Rect(x: 500, y: 0, width: 500, height: 800) // right half of a
        XCTAssertEqual(Geometry.screenIndex(for: win, screens: [a, b]), 0)
        XCTAssertEqual(Geometry.screenIndex(for: Rect(x: 2500, y: 10, width: 10, height: 10), screens: [a, b]), 1)
        XCTAssertEqual(Geometry.move(win, from: a, to: b), Rect(x: 2000, y: 0, width: 1000, height: 1000))
        XCTAssertEqual(Geometry.spatialOrder([b, a]), [1, 0])
    }
}

final class DivvyImportTests: XCTestCase {
    /// The layout Divvy writes, as shown by `plutil -convert xml1` on a real preference file.
    let divvyArchiveXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>$archiver</key><string>NSKeyedArchiver</string>
      <key>$objects</key>
      <array>
        <string>$null</string>
        <dict>
          <key>$class</key><dict><key>CF$UID</key><integer>5</integer></dict>
          <key>NS.objects</key><array><dict><key>CF$UID</key><integer>2</integer></dict></array>
        </dict>
        <dict>
          <key>$class</key><dict><key>CF$UID</key><integer>4</integer></dict>
          <key>enabled</key><true/>
          <key>global</key><false/>
          <key>keyComboCode</key><integer>37</integer>
          <key>keyComboFlags</key><integer>0</integer>
          <key>nameKey</key><dict><key>CF$UID</key><integer>3</integer></dict>
          <key>selectionEndColumn</key><integer>2</integer>
          <key>selectionEndRow</key><integer>5</integer>
          <key>selectionStartColumn</key><integer>0</integer>
          <key>selectionStartRow</key><integer>0</integer>
          <key>sizeColumns</key><integer>6</integer>
          <key>sizeRows</key><integer>6</integer>
          <key>subdivided</key><false/>
        </dict>
        <string>Left Half</string>
        <dict>
          <key>$classes</key><array><string>Shortcut</string><string>NSObject</string></array>
          <key>$classname</key><string>Shortcut</string>
        </dict>
        <dict>
          <key>$classes</key><array><string>NSMutableArray</string><string>NSArray</string><string>NSObject</string></array>
          <key>$classname</key><string>NSMutableArray</string>
        </dict>
      </array>
      <key>$top</key><dict><key>root</key><dict><key>CF$UID</key><integer>1</integer></dict></dict>
      <key>$version</key><integer>100000</integer>
    </dict>
    </plist>
    """

    func testDecodesRealDivvyArchive() throws {
        let shortcuts = try DivvyImporter.decodeShortcuts(Data(divvyArchiveXML.utf8))
        XCTAssertEqual(shortcuts, [DivvyShortcut(name: "Left Half", global: false, keyCode: 37, cocoaFlags: 0,
                                                 startColumn: 0, startRow: 0, endColumn: 2, endRow: 5,
                                                 columns: 6, rows: 6)])
    }

    func testReadsPreferenceDomainAndRendersValidConfig() throws {
        let shortcuts = [
            DivvyShortcut(name: "Left Half", global: false, keyCode: 37, cocoaFlags: 0,
                          startColumn: 0, startRow: 0, endColumn: 2, endRow: 5, columns: 6, rows: 6),
            DivvyShortcut(name: "Right Third", global: true, keyCode: 124, cocoaFlags: (1 << 18) | (1 << 19),
                          startColumn: 2, startRow: 1, endColumn: 1, endRow: 0, columns: 3, rows: 2),
            DivvyShortcut(name: "Old", enabled: false, global: true, keyCode: 0, cocoaFlags: 1 << 20,
                          startColumn: 0, startRow: 0, endColumn: 0, endRow: 0, columns: 6, rows: 6),
            DivvyShortcut(name: "Dup", global: false, keyCode: 37, cocoaFlags: 0,
                          startColumn: 0, startRow: 0, endColumn: 5, endRow: 5, columns: 6, rows: 6),
            DivvyShortcut(name: "Fine", global: true, keyCode: 0, cocoaFlags: (1 << 18) | (1 << 20),
                          startColumn: 0, startRow: 0, endColumn: 9, endRow: 3, columns: 6, rows: 6, subdivided: true),
        ]
        let domain: [String: Any] = [
            "shortcuts": try DivvyImporter.encodeShortcuts(shortcuts),
            "licenseKey": "secret",
            "useGlobalHotkey": true,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0)
        let prefs = try DivvyImporter.readPreferences(data)
        XCTAssertEqual(prefs.shortcuts, shortcuts)
        XCTAssertEqual(prefs.otherKeys, ["licenseKey", "useGlobalHotkey"])

        let text = DivvyImporter.renderConfig(prefs, source: "test")
        XCTAssertFalse(text.contains("secret"))
        let config = try Config.parse(text)
        XCTAssertEqual(config.settings.grid, GridSize(columns: 6, rows: 6))
        XCTAssertNotNil(config.settings.leader)
        XCTAssertEqual(config.shortcuts.map(\.name), ["Left Half", "Right Third", "Fine"])

        let left = config.shortcuts[0]
        XCTAssertFalse(left.global)
        XCTAssertEqual(left.combo, KeyCombo(modifiers: [], key: .code(37)))
        XCTAssertEqual(left.action, .place(CellRange(x: 0, y: 0, w: 3, h: 6), grid: GridSize(columns: 6, rows: 6)))

        let right = config.shortcuts[1]
        XCTAssertTrue(right.global)
        XCTAssertEqual(right.combo.description, "ctrl+alt+right")
        XCTAssertEqual(right.action, .place(CellRange(x: 1, y: 0, w: 2, h: 2), grid: GridSize(columns: 3, rows: 2)))

        XCTAssertEqual(config.shortcuts[2].action,
                       .place(CellRange(x: 0, y: 0, w: 10, h: 4), grid: GridSize(columns: 12, rows: 12)))
        XCTAssertTrue(text.contains("# [[shortcut]]\n# name = \"Old\""))
        XCTAssertTrue(text.contains("same keys as 'Left Half'"))
    }

    func testLayoutLookupNamesCharacterKeys() {
        let converted = DivvyImporter.convert(
            DivvyShortcut(name: "", global: true, keyCode: 6, cocoaFlags: 1 << 18,
                          startColumn: 0, startRow: 0, endColumn: 0, endRow: 0, columns: 1, rows: 1),
            layoutCharacter: { $0 == 6 ? "Y" : nil })
        XCTAssertEqual(converted.combo, "ctrl+y")
    }
}
