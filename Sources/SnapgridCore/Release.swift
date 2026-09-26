import Foundation

/// Dotted version like "0.2.0" (a leading "v", as in git tags, is ignored).
public struct AppVersion: Comparable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }
}

public struct Release: Equatable {
    public var version: AppVersion
    public var zipURL: URL
    public var pageURL: URL?
    public var notes: String
}

public enum GitHubReleases {
    public struct ParseError: Error, CustomStringConvertible {
        public let description: String
    }

    public static func latestURL(repo: String) -> URL? {
        URL(string: "https://api.github.com/repos/\(repo)/releases/latest")
    }

    /// Reads the `releases/latest` API response; the release needs a `Snapgrid-….zip` asset.
    public static func parseLatest(_ data: Data) throws -> Release {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            throw ParseError(description: "unexpected answer from GitHub")
        }
        guard let version = AppVersion(tag) else {
            throw ParseError(description: "release tag '\(tag)' is not a version like v1.2.3")
        }
        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let zip = assets.first(where: { ($0["name"] as? String).map { $0.hasPrefix("Snapgrid") && $0.hasSuffix(".zip") } ?? false }),
              let link = zip["browser_download_url"] as? String, let zipURL = URL(string: link) else {
            throw ParseError(description: "release \(tag) has no Snapgrid .zip attached")
        }
        return Release(version: version, zipURL: zipURL,
                       pageURL: (json["html_url"] as? String).flatMap(URL.init(string:)),
                       notes: json["body"] as? String ?? "")
    }

    /// Why a `releases/latest` request failed, or nil for a usable answer.
    public static func failure(status: Int) -> String? {
        switch status {
        case 200: return nil
        case 404: return "No release has been published yet."
        default: return "GitHub answered with status \(status)."
        }
    }
}

/// When the updater checks and installs, and what it accepts.
public enum UpdatePolicy {
    /// Automatic checks run at launch and every few hours, but at most once per this interval.
    public static let checkInterval: TimeInterval = 24 * 3600
    public static let timerInterval: TimeInterval = 6 * 3600
    /// Automatic installs wait until the Mac has been idle this long, since Snapgrid restarts.
    public static let idleBeforeInstall: TimeInterval = 600

    public static func isCheckDue(lastCheck: Date?, now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastCheck ?? .distantPast) > checkInterval
    }

    /// `appAllows` is false while the grid panel is open or Settings has unsaved edits.
    public static func shouldInstallAutomatically(idleSeconds: TimeInterval, appAllows: Bool) -> Bool {
        idleSeconds >= idleBeforeInstall && appAllows
    }

    /// The code requirement a download must meet: Apple-issued certificate, Snapgrid's
    /// bundle identifier and the same team as the running copy.
    public static func signingRequirement(identifier: String, team: String) -> String {
        "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }

    /// A notification is sent once per version, and only for automatic checks: a check
    /// from the menu answers with a dialog instead.
    public static func shouldNotify(about version: AppVersion, lastNotified: String?, userInitiated: Bool) -> Bool {
        !userInitiated && lastNotified != version.description
    }

    /// A download is only installed if its bundle version is newer than the running one.
    public static func isNewer(bundleVersion: String?, than current: AppVersion) -> Bool {
        guard let version = bundleVersion.flatMap(AppVersion.init) else { return false }
        return version > current
    }
}
