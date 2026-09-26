import Foundation
import GridKeysCore
#if os(macOS)
import AppKit
#endif

func runDaemon(configURL: URL) -> Never {
    #if os(macOS)
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate(configURL: configURL)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
    exit(0)
    #else
    FileHandle.standardError.write(Data("gridkeys: the daemon only runs on macOS\n".utf8))
    exit(1)
    #endif
}

func layoutLookup() -> ((UInt32) -> Character?)? {
    #if os(macOS)
    let table = KeyboardLayout.characterTable()
    return { table[$0] }
    #else
    return nil
    #endif
}

let arguments = CommandLine.arguments
let command = arguments.dropFirst().first

do {
    switch command {
    case nil:
        // Launched from the .app bundle (Finder, login item): run the daemon.
        // From a terminal, show help instead of silently starting a second copy.
        if isatty(STDIN_FILENO) != 0 { print(CLI.usage) } else { runDaemon(configURL: Config.defaultPath) }
    case "run":
        let opts = try CLI.Options(arguments.dropFirst(2), valued: ["--config"])
        runDaemon(configURL: opts.configURL())
    case "check":
        let opts = try CLI.Options(arguments.dropFirst(2), valued: ["--config"])
        try CLI.check(opts.configURL())
    case "init":
        let opts = try CLI.Options(arguments.dropFirst(2), valued: ["--config"])
        let url = opts.configURL()
        try CLI.writeDefaultConfig(to: url, force: opts.flags.contains("--force"))
        print("Wrote \(url.path)")
    case "import-divvy":
        let opts = try CLI.Options(arguments.dropFirst(2), valued: ["--config", "--plist", "--output"])
        try CLI.importDivvy(opts, layoutCharacter: layoutLookup())
    case "reload":
        #if os(macOS)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("dev.gridkeys.reload"), object: nil, userInfo: nil, deliverImmediately: true)
        print("Reload requested")
        #else
        throw CLI.Failure(message: "reload only works on macOS")
        #endif
    case "help", "-h", "--help":
        print(CLI.usage)
    case "version", "--version":
        print(CLI.version)
    case let other?:
        throw CLI.Failure(message: "unknown command '\(other)'\n\n\(CLI.usage)", code: 2)
    }
} catch let failure as CLI.Failure {
    FileHandle.standardError.write(Data("gridkeys: \(failure.message)\n".utf8))
    exit(failure.code)
} catch {
    FileHandle.standardError.write(Data("gridkeys: \(error)\n".utf8))
    exit(1)
}
