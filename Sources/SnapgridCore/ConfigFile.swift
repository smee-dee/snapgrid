import Foundation

public enum ConfigFile {
    public struct ExistsError: Error, CustomStringConvertible {
        public let path: String
        public var description: String { "\(path) already exists (use --force to replace it; a .bak copy is kept)" }
    }

    /// Writes the config, keeping the previous file as `<name>.bak`. With `force` off an
    /// existing file is an error. Symlinks (iCloud sync) are followed, because an atomic
    /// write would otherwise replace the link with a plain file.
    public static func write(_ text: String, to url: URL, force: Bool) throws {
        let url = url.resolvingSymlinksInPath()
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            guard force else { throw ExistsError(path: url.path) }
            let backup = url.appendingPathExtension("bak")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: url, to: backup)
        }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
