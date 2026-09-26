import Foundation

/// Semantic version like "0.2.0" or "0.4.0-beta.2" (a leading "v", as in git tags, is ignored).
/// Pre-releases sort before their release: 0.4.0-beta.1 < 0.4.0-beta.2 < 0.4.0.
public struct AppVersion: Comparable, CustomStringConvertible {
    public let parts: [Int]
    /// Pre-release identifiers, e.g. ["beta", "2"]; empty for a release.
    public let prerelease: [String]

    public init?(_ text: String) {
        var trimmed = text.hasPrefix("v") ? Substring(text.dropFirst()) : Substring(text)
        if let plus = trimmed.firstIndex(of: "+") { trimmed = trimmed[..<plus] }
        var pre: [String] = []
        if let dash = trimmed.firstIndex(of: "-") {
            pre = trimmed[trimmed.index(after: dash)...].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard pre.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber } }) else { return nil }
            trimmed = trimmed[..<dash]
        }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        self.parts = parts.compactMap { $0 }
        prerelease = pre
    }

    public var isPrerelease: Bool { !prerelease.isEmpty }

    public var description: String {
        parts.map(String.init).joined(separator: ".") + (isPrerelease ? "-" + prerelease.joined(separator: ".") : "")
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        if a.prerelease.isEmpty || b.prerelease.isEmpty { return !a.prerelease.isEmpty && b.prerelease.isEmpty }
        for (x, y) in zip(a.prerelease, b.prerelease) where x != y {
            switch (Int(x), Int(y)) {
            case let (i?, j?): return i < j
            case (.some, nil): return true    // numeric identifiers sort before words
            case (nil, .some): return false
            case (nil, nil): return x < y
            }
        }
        return a.prerelease.count < b.prerelease.count
    }
}

public struct Release: Equatable {
    public var version: AppVersion
    public var zipURL: URL
    public var pageURL: URL?
    public var notes: String
    /// Marked as a pre-release on GitHub (beta channel only).
    public var isPrerelease: Bool = false
}

/// Which releases an installed copy updates to.
public enum UpdateChannel: String, CaseIterable {
    case stable, beta
}

public enum GitHubReleases {
    public struct ParseError: Error, CustomStringConvertible {
        public let description: String
    }

    public static func latestURL(repo: String) -> URL? {
        URL(string: "https://api.github.com/repos/\(repo)/releases/latest")
    }

    /// Recent releases including pre-releases, which `releases/latest` leaves out.
    public static func listURL(repo: String) -> URL? {
        URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=30")
    }

    /// Reads the `releases` API response. Drafts and releases without a usable zip are skipped.
    public static func parseList(_ data: Data) throws -> [Release] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ParseError(description: "unexpected answer from GitHub")
        }
        return list.filter { ($0["draft"] as? Bool) != true }.compactMap { try? parse($0) }
    }

    /// Reads the `releases/latest` API response; the release needs a `Snapgrid-….zip` asset.
    public static func parseLatest(_ data: Data) throws -> Release {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError(description: "unexpected answer from GitHub")
        }
        return try parse(json)
    }

    private static func parse(_ json: [String: Any]) throws -> Release {
        guard let tag = json["tag_name"] as? String else {
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
                       notes: json["body"] as? String ?? "",
                       isPrerelease: (json["prerelease"] as? Bool) == true || version.isPrerelease)
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

    /// The newest release on `channel` that's newer than `current`. Leaving the beta channel
    /// never downgrades by itself: a beta build waits for a newer stable release.
    public static func update(from releases: [Release], channel: UpdateChannel, current: AppVersion) -> Release? {
        releases.filter { (channel == .beta || !$0.isPrerelease) && $0.version > current }
            .max { $0.version < $1.version }
    }

    /// On the stable channel while running a beta: the latest stable release, offered as an explicit
    /// "switch back". nil when the normal update already leads to stable, or nothing applies.
    public static func stableFallback(from releases: [Release], channel: UpdateChannel, current: AppVersion) -> Release? {
        guard channel == .stable, current.isPrerelease,
              update(from: releases, channel: .stable, current: current) == nil else { return nil }
        return releases.filter { !$0.isPrerelease }.max { $0.version < $1.version }
    }

    /// A download is installed only if it's the release that was picked, and newer than the
    /// running copy unless the user chose to switch back to stable.
    public static func accepts(bundleVersion: String?, for release: Release, current: AppVersion,
                               allowDowngrade: Bool = false) -> Bool {
        guard let version = bundleVersion.flatMap(AppVersion.init), version == release.version else { return false }
        return version > current || (allowDowngrade && !release.isPrerelease && version != current)
    }
}
