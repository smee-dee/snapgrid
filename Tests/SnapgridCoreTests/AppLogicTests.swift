import XCTest
@testable import SnapgridCore

final class ConfigFileTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("configfile-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    func testCreatesRefusesAndBacksUp() throws {
        let url = root.appendingPathComponent("snapgrid/config.toml")
        try ConfigFile.write("one", to: url, force: false)
        XCTAssertEqual(read(url), "one")

        XCTAssertThrowsError(try ConfigFile.write("two", to: url, force: false)) { error in
            XCTAssertTrue(error is ConfigFile.ExistsError)
        }
        XCTAssertEqual(read(url), "one")

        try ConfigFile.write("two", to: url, force: true)
        XCTAssertEqual(read(url), "two")
        XCTAssertEqual(read(url.appendingPathExtension("bak")), "one")
    }

    func testWritesThroughTheICloudSymlink() throws {
        let real = root.appendingPathComponent("drive/config.toml")
        let link = root.appendingPathComponent("home/config.toml")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "old".write(to: real, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        try ConfigFile.write("new", to: link, force: true)
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path))
        XCTAssertEqual(read(real), "new")
        XCTAssertEqual(read(real.appendingPathExtension("bak")), "old")
    }
}

final class HotKeyPlanTests: XCTestCase {
    func config(_ text: String) throws -> Config { try Config.parse(text) }

    func testSplitsGlobalAndLocalShortcuts() throws {
        let c = try Config.parse(DefaultConfig.text)
        XCTAssertEqual(c.globalShortcuts.count + c.localShortcuts.count, c.shortcuts.count)
        XCTAssertTrue(c.globalShortcuts.allSatisfy(\.global))
        XCTAssertFalse(c.localShortcuts.contains(where: \.global))
    }

    func testLeaderIsOnlyRegisteredWhenUseful() throws {
        let local = "[[shortcut]]\nkeys = \"l\"\ncells = \"0,0 1x1\"\nglobal = false"
        XCTAssertFalse(try config("[settings]\nshow_grid = true").registersLeader)
        XCTAssertTrue(try config("[settings]\nleader = \"ctrl+space\"").registersLeader)
        XCTAssertFalse(try config("[settings]\nleader = \"ctrl+space\"\nshow_grid = false").registersLeader)
        XCTAssertTrue(try config("[settings]\nleader = \"ctrl+space\"\nshow_grid = false\n" + local).registersLeader)
    }

    func testEscapeCancelsUnlessALocalShortcutUsesIt() throws {
        XCTAssertTrue(try config("[settings]\nleader = \"ctrl+space\"").escapeCancelsLeader)
        let esc = "[settings]\nleader = \"ctrl+space\"\n[[shortcut]]\nkeys = \"escape\"\ncells = \"0,0 1x1\"\nglobal = false"
        XCTAssertFalse(try config(esc).escapeCancelsLeader)
    }

    func testErrorLineMapsToShortcut() {
        let text = "[settings]\ngrid = \"6x6\"\n\n[[shortcut]]\nkeys = \"a\"\n\n[[shortcut]]\nkeys = \"b\"\n"
        XCTAssertNil(Config.shortcutIndex(forErrorLine: 2, in: text))
        XCTAssertEqual(Config.shortcutIndex(forErrorLine: 5, in: text), 0)
        XCTAssertEqual(Config.shortcutIndex(forErrorLine: 7, in: text), 1)
        XCTAssertEqual(Config.shortcutIndex(forErrorLine: 8, in: text), 1)
    }

    func testSettingsProblemsPointAtTheShortcut() throws {
        // What Settings does: render the drafts, parse them back, and map the error line.
        var c = Config()
        c.shortcuts = [
            Shortcut(name: "Fine", combo: try KeyCombo.parse("ctrl+a"), action: .place(CellRange(x: 0, y: 0, w: 1, h: 1), grid: c.settings.grid), global: true),
            Shortcut(name: "Too wide", combo: try KeyCombo.parse("ctrl+b"), action: .place(CellRange(x: 5, y: 0, w: 3, h: 1), grid: c.settings.grid), global: true),
        ]
        let text = c.render()
        XCTAssertThrowsError(try Config.parse(text)) { error in
            let line = (error as? ConfigError)?.line
            XCTAssertEqual(line.flatMap { Config.shortcutIndex(forErrorLine: $0, in: text) }, 1)
        }
    }

    func testMenuSymbols() throws {
        XCTAssertEqual(try KeyCombo.parse("shift+cmd+d").symbols, "⇧⌘D")
        XCTAssertEqual(try KeyCombo.parse("ctrl+alt+left").symbols, "⌃⌥←")
        XCTAssertEqual(try KeyCombo.parse("ctrl+space").symbols, "⌃Space")
        XCTAssertEqual(try KeyCombo.parse("f13").symbols, "F13")
        XCTAssertEqual(KeyCombo.escape.symbols, "⎋")
    }
}

final class SetupTests: XCTestCase {
    func testPreferredSource() {
        XCTAssertEqual(Setup.preferredSource(hasCurrent: true, hasCloud: true, hasDivvy: true), .keep)
        XCTAssertEqual(Setup.preferredSource(hasCurrent: false, hasCloud: true, hasDivvy: true), .iCloud)
        XCTAssertEqual(Setup.preferredSource(hasCurrent: false, hasCloud: false, hasDivvy: true), .divvy)
        XCTAssertEqual(Setup.preferredSource(hasCurrent: false, hasCloud: false, hasDivvy: false), .example)
    }

    func testSummary() throws {
        let c = try Config.parse(DefaultConfig.text)
        let summary = Setup.summary(for: c)
        XCTAssertTrue(summary.hasPrefix("\(c.shortcuts.count) shortcuts are ready."))
        XCTAssertTrue(summary.contains("press ⌃⌥Space, then the key"))
        XCTAssertEqual(Setup.summary(for: Config()), "0 shortcuts are ready.")
        XCTAssertTrue(Setup.summary(for: nil).contains("error"))
    }
}

final class CommandLineOptionsTests: XCTestCase {
    func testParsesFlagsValuesAndWords() throws {
        let o = try CommandLineOptions(["--plist", "~/Divvy.plist", "--force", "extra", "--output", "-"],
                                       valued: ["--plist", "--output"])
        XCTAssertEqual(o.values, ["--plist": "~/Divvy.plist", "--output": "-"])
        XCTAssertEqual(o.flags, ["--force"])
        XCTAssertEqual(o.positional, ["extra"])
        XCTAssertThrowsError(try CommandLineOptions(["--config"], valued: ["--config"]))
    }

    func testConfigPath() throws {
        let fallback = URL(fileURLWithPath: "/tmp/default.toml")
        XCTAssertEqual(try CommandLineOptions([], valued: ["--config"]).configURL(default: fallback), fallback)
        let custom = try CommandLineOptions(["--config", "~/x.toml"], valued: ["--config"]).configURL(default: fallback)
        XCTAssertEqual(custom.path, NSHomeDirectory() + "/x.toml")
    }
}

final class DocsTests: XCTestCase {
    func testREADMEConfigReferenceParses() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("README.md")
        let readme = try String(contentsOf: url, encoding: .utf8)
        let section = try XCTUnwrap(readme.range(of: "## Config reference"))
        let block = try XCTUnwrap(readme[section.upperBound...].range(of: "```toml\n"))
        let end = try XCTUnwrap(readme[block.upperBound...].range(of: "```"))
        let config = try Config.parse(String(readme[block.upperBound..<end.lowerBound]))
        XCTAssertNotNil(config.settings.margin)
        XCTAssertEqual(config.shortcuts.count, 2)
    }
}
