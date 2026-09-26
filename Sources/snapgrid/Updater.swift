#if os(macOS)
import AppKit
import Security
import SnapgridCore

/// Checks GitHub Releases for a newer Snapgrid and installs it in place.
/// A download is only installed if it's signed by the same team as the running app,
/// which also keeps the Accessibility permission working after the update.
@MainActor
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle, checking, upToDate, installing
        case available(Release)
        case failed(String)
    }

    struct Failure: Error { let message: String }

    static let automaticKey = "checkForUpdatesAutomatically"
    static let lastCheckKey = "lastUpdateCheck"

    @Published private(set) var state: State = .idle
    var onStateChange: () -> Void = {}

    /// "owner/repo", written into Info.plist by scripts/build-app.sh.
    let repo = (Bundle.main.object(forInfoDictionaryKey: "SnapgridUpdateRepo") as? String).flatMap { $0.isEmpty ? nil : $0 }
    let currentVersion = AppVersion(CLI.version)!
    private var timer: Timer?

    var automatic: Bool {
        get { UserDefaults.standard.object(forKey: Self.automaticKey) as? Bool ?? true }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: Self.automaticKey)
        }
    }

    /// Checks at launch and then every few hours, at most once a day.
    func startAutomaticChecks() {
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
    }

    private func checkIfDue() {
        guard automatic, repo != nil else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        if Date().timeIntervalSince(last) > 24 * 3600 { Task { await check(userInitiated: false) } }
    }

    func check(userInitiated: Bool) async {
        guard let repo, let url = GitHubReleases.latestURL(repo: repo) else {
            state = .failed("This build has no update source (it was built without a GitHub repo).")
            onStateChange()
            return
        }
        if state == .checking || state == .installing { return }
        state = .checking
        onStateChange()
        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { throw Failure(message: "No release has been published yet.") }
            guard status == 200 else { throw Failure(message: "GitHub answered with status \(status).") }
            let release = try GitHubReleases.parseLatest(data)
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            state = release.version > currentVersion ? .available(release) : .upToDate
        } catch {
            state = userInitiated ? .failed(Self.message(error)) : .idle
        }
        onStateChange()
    }

    func install(_ release: Release) async {
        state = .installing
        onStateChange()
        do {
            let (zip, _) = try await URLSession.shared.download(from: release.zipURL)
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("snapgrid-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            let newApp = work.appendingPathComponent("Snapgrid.app")
            try verify(newApp)
            let target = Bundle.main.bundleURL
            _ = try FileManager.default.replaceItemAt(target, withItemAt: newApp)
            try? FileManager.default.removeItem(at: work)
            relaunch(target)
        } catch {
            state = .failed("Update failed: \(Self.message(error))")
            onStateChange()
        }
    }

    private func verify(_ app: URL) throws {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            throw Failure(message: "Only the installed Snapgrid.app can update itself.")
        }
        guard let team = Self.teamIdentifier(of: Bundle.main.bundleURL) else {
            throw Failure(message: "This copy isn't signed with a developer certificate, so the download can't be verified. Download the new version by hand.")
        }
        let id = Bundle.main.bundleIdentifier ?? "dev.snapgrid.Snapgrid"
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let text = "anchor apple generic and identifier \"\(id)\" and certificate leaf[subject.OU] = \"\(team)\""
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement else {
            throw Failure(message: "The download doesn't contain Snapgrid.app.")
        }
        let status = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), requirement)
        guard status == errSecSuccess else {
            throw Failure(message: "The download isn't signed by the same developer as this copy (error \(status)).")
        }
        guard let version = (Bundle(url: app)?.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init),
              version > currentVersion else {
            throw Failure(message: "The download isn't newer than the installed version.")
        }
    }

    static func teamIdentifier(of url: URL) -> String? {
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Starts the new copy once this one has quit, so the two never compete for the hotkeys.
    private func relaunch(_ app: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure(message: "\(tool) failed (\(process.terminationStatus))") }
    }

    private static func message(_ error: Error) -> String {
        (error as? Failure)?.message ?? (error as? GitHubReleases.ParseError)?.description ?? error.localizedDescription
    }
}
#endif
