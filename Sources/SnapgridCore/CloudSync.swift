import Foundation

/// Keeps the config in a synced folder (iCloud Drive) and leaves a symlink at the usual path,
/// so the app, the CLI and text editors all keep using ~/.config/snapgrid/config.toml.
/// Apple's iCloud key-value store would need an iCloud entitlement (paid developer account);
/// iCloud Drive syncs any file without one.
public struct CloudSync {
    public let driveRoot: URL
    public let configURL: URL

    public init(driveRoot: URL, folderName: String = "Snapgrid") {
        self.driveRoot = driveRoot
        configURL = driveRoot.appendingPathComponent(folderName).appendingPathComponent("config.toml")
    }

    public static var iCloudDrive: CloudSync {
        CloudSync(driveRoot: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"))
    }

    public var isAvailable: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: driveRoot.path, isDirectory: &isDir) && isDir.boolValue
    }

    public var hasCloudConfig: Bool { FileManager.default.fileExists(atPath: configURL.path) }

    public func isEnabled(for local: URL) -> Bool {
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: local.path) else { return false }
        return URL(fileURLWithPath: dest).standardizedFileURL.path == configURL.standardizedFileURL.path
    }

    /// Moves the config into the synced folder. With `useCloudCopy` and an existing synced
    /// config (e.g. from another Mac), that one wins; otherwise this Mac's config replaces it.
    /// Whatever gets replaced is kept next to it as `config.toml.bak`.
    public func enable(for local: URL, useCloudCopy: Bool) throws {
        guard !isEnabled(for: local) else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let localText = try? String(contentsOf: local, encoding: .utf8)
        if !(useCloudCopy && hasCloudConfig) {
            if let cloudText = try? String(contentsOf: configURL, encoding: .utf8) {
                try cloudText.write(to: configURL.appendingPathExtension("bak"), atomically: true, encoding: .utf8)
            }
            try (localText ?? DefaultConfig.text).write(to: configURL, atomically: true, encoding: .utf8)
        } else if let localText {
            try localText.write(to: local.appendingPathExtension("bak"), atomically: true, encoding: .utf8)
        }
        if localText != nil || (try? fm.destinationOfSymbolicLink(atPath: local.path)) != nil {
            try fm.removeItem(at: local)
        }
        try fm.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: local, withDestinationURL: configURL)
    }

    /// Replaces the symlink with a local copy. The synced file stays for other Macs.
    public func disable(for local: URL) throws {
        guard isEnabled(for: local) else { return }
        let text = try String(contentsOf: configURL, encoding: .utf8)
        try FileManager.default.removeItem(at: local)
        try text.write(to: local, atomically: true, encoding: .utf8)
    }
}
