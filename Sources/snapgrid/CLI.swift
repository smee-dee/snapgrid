import Foundation
import SnapgridCore

enum CLI {
    static let version = "0.1.0"

    static let usage = """
    snapgrid \(version) — Divvy-style grid window placement with global shortcuts

    USAGE
      snapgrid run [--config PATH]          Run the hotkey daemon in the foreground
      snapgrid check [--config PATH]        Validate the config and list shortcuts
      snapgrid init [--config PATH] [--force]
                                            Write a starter config
      snapgrid import-divvy [--plist FILE] [--output PATH|-] [--force]
                                            Convert your Divvy shortcuts to a Snapgrid config
      snapgrid reload                       Ask the running app to reload its config
      snapgrid help | version

    Default config: \(Config.defaultPath.path)
    """

    struct Failure: Error { let message: String; var code: Int32 = 1 }

    struct Options {
        var positional: [String] = []
        var flags: Set<String> = []
        var values: [String: String] = [:]

        init(_ args: ArraySlice<String>, valued: Set<String>) throws {
            var it = args.makeIterator()
            while let arg = it.next() {
                if valued.contains(arg) {
                    guard let v = it.next() else { throw Failure(message: "\(arg) needs a value") }
                    values[arg] = v
                } else if arg.hasPrefix("--") {
                    flags.insert(arg)
                } else {
                    positional.append(arg)
                }
            }
        }

        func configURL() -> URL {
            values["--config"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? Config.defaultPath
        }
    }

    static func writeDefaultConfig(to url: URL, force: Bool) throws {
        try write(DefaultConfig.text, to: url, force: force)
    }

    static func write(_ text: String, to url: URL, force: Bool) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            guard force else {
                throw Failure(message: "\(url.path) already exists (use --force to replace it; a .bak copy is kept)")
            }
            let backup = url.appendingPathExtension("bak")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: url, to: backup)
        }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func check(_ url: URL) throws {
        let config: Config
        do { config = try Config.load(from: url) }
        catch { throw Failure(message: "\(url.path): \(error)") }
        print("\(url.path): OK")
        print("grid \(config.settings.grid), gap \(config.settings.gap)"
              + (config.settings.leader.map { ", leader \($0) (\(config.settings.leaderTimeout)s)" } ?? ""))
        for s in config.shortcuts {
            let what: String
            switch s.action {
            case .place(let cells, let grid): what = "cells \(cells) of \(grid)"
            case .nextScreen: what = "next screen"
            case .previousScreen: what = "previous screen"
            }
            let keys = "\(s.combo)\(s.global ? "" : " (local)")"
            print("  \(keys.padding(toLength: 28, withPad: " ", startingAt: 0)) \(s.name) — \(what)")
        }
        for w in config.warnings { print("warning: \(w)") }
    }

    static func importDivvy(_ opts: Options, layoutCharacter: ((UInt32) -> Character?)?) throws {
        let data: Data
        let source: String
        if let path = opts.values["--plist"] {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard let d = FileManager.default.contents(atPath: url.path) else {
                throw Failure(message: "cannot read \(url.path)")
            }
            (data, source) = (d, url.lastPathComponent)
        } else {
            (data, source) = try readInstalledDivvyPreferences()
        }

        let prefs: DivvyImporter.Preferences
        do { prefs = try DivvyImporter.readPreferences(data) }
        catch { throw Failure(message: "\(source): \(error)") }
        let text = DivvyImporter.renderConfig(prefs, source: source, layoutCharacter: layoutCharacter)

        do { _ = try Config.parse(text) }
        catch { throw Failure(message: "internal error: generated config does not validate (\(error))\n\n\(text)") }

        let output = opts.values["--output"]
        if output == "-" {
            print(text, terminator: "")
            return
        }
        let url = output.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? opts.configURL()
        try write(text, to: url, force: opts.flags.contains("--force"))
        let local = prefs.shortcuts.filter { !$0.global }.count
        print("Imported \(prefs.shortcuts.count) Divvy shortcuts (\(local) local) into \(url.path)")
        print("Review it, then run: snapgrid check")
    }

    /// Reads Divvy's preferences via `defaults export`, which works for both the
    /// direct-download and App Store builds without touching the licence file directly.
    static func readInstalledDivvyPreferences() throws -> (Data, String) {
        #if os(macOS)
        for domain in DivvyImporter.domains {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            process.arguments = ["export", domain, "-"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0, !data.isEmpty,
               (try? DivvyImporter.readPreferences(data)) != nil {
                return (data, domain)
            }
        }
        let container = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.mizage.Divvy/Data/Library/Preferences/com.mizage.Divvy.plist")
        if let data = FileManager.default.contents(atPath: container.path) {
            return (data, container.path)
        }
        throw Failure(message: "no Divvy preferences found (tried \(DivvyImporter.domains.joined(separator: ", ")) and the App Store container). Use --plist FILE.")
        #else
        throw Failure(message: "reading installed Divvy preferences only works on macOS; pass --plist FILE")
        #endif
    }
}
