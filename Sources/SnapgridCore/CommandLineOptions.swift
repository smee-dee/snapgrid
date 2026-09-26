import Foundation

/// Arguments after the command: `--flag`, `--option value` (for the names in `valued`) and plain words.
public struct CommandLineOptions {
    public struct MissingValue: Error, CustomStringConvertible {
        public let option: String
        public var description: String { "\(option) needs a value" }
    }

    public var positional: [String] = []
    public var flags: Set<String> = []
    public var values: [String: String] = [:]

    public init<S: Sequence>(_ args: S, valued: Set<String>) throws where S.Element == String {
        var it = args.makeIterator()
        while let arg = it.next() {
            if valued.contains(arg) {
                guard let v = it.next() else { throw MissingValue(option: arg) }
                values[arg] = v
            } else if arg.hasPrefix("--") {
                flags.insert(arg)
            } else {
                positional.append(arg)
            }
        }
    }

    /// `--config PATH` with `~` expanded, else the default location.
    public func configURL(default fallback: URL = Config.defaultPath) -> URL {
        values["--config"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? fallback
    }
}
