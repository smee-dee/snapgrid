import XCTest
@testable import SnapgridCore
#if canImport(Security)
import Security
#endif

final class ReleaseTests: XCTestCase {
    func testVersionOrdering() throws {
        let v = { (s: String) in try XCTUnwrap(AppVersion(s)) }
        XCTAssertLessThan(try v("0.1.0"), try v("0.2.0"))
        XCTAssertLessThan(try v("0.9"), try v("0.10.0"))
        XCTAssertEqual(try v("v1.2"), try v("1.2.0"))
        XCTAssertNil(AppVersion("1.x"))
        XCTAssertNil(AppVersion(""))
    }

    func testPrereleaseOrdering() throws {
        let order = ["0.3.1", "0.4.0-alpha.1", "0.4.0-beta.1", "0.4.0-beta.2", "0.4.0-beta.10", "0.4.0-rc.1", "0.4.0", "0.4.1"]
        let versions = try order.map { try XCTUnwrap(AppVersion($0)) }
        for (a, b) in zip(versions, versions.dropFirst()) { XCTAssertLessThan(a, b, "\(a) < \(b)") }
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.0.0-1")), try XCTUnwrap(AppVersion("1.0.0-beta")))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.0.0-beta")), try XCTUnwrap(AppVersion("1.0.0-beta.1")))
        XCTAssertEqual(AppVersion("v0.4.0-beta.2+build.7")?.description, "0.4.0-beta.2")
        XCTAssertEqual(AppVersion("0.4.0-beta.2")?.prerelease, ["beta", "2"])
        XCTAssertTrue(AppVersion("0.4.0-beta.2")!.isPrerelease)
        XCTAssertFalse(AppVersion("0.4.0")!.isPrerelease)
        XCTAssertNil(AppVersion("0.4.0-"))
        XCTAssertNil(AppVersion("0.4.0-beta..1"))
        XCTAssertNil(AppVersion("0.4.0-be_ta"))
    }

    func testParsesLatestRelease() throws {
        let json = """
        {"tag_name": "v0.2.0", "html_url": "https://github.com/me/snapgrid/releases/tag/v0.2.0", "body": "Fixes",
         "assets": [{"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"},
                    {"name": "Snapgrid-0.2.0.zip", "browser_download_url": "https://example.com/Snapgrid-0.2.0.zip"}]}
        """
        let release = try GitHubReleases.parseLatest(Data(json.utf8))
        XCTAssertEqual(release.version, AppVersion("0.2.0"))
        XCTAssertEqual(release.zipURL.absoluteString, "https://example.com/Snapgrid-0.2.0.zip")
        XCTAssertEqual(release.notes, "Fixes")

        XCTAssertThrowsError(try GitHubReleases.parseLatest(Data(#"{"tag_name": "v0.3.0", "assets": []}"#.utf8)))
        XCTAssertThrowsError(try GitHubReleases.parseLatest(Data(#"{"tag_name": "latest", "assets": []}"#.utf8)))
        XCTAssertThrowsError(try GitHubReleases.parseLatest(Data("not json".utf8)))
    }

    func testRequestStatus() {
        XCTAssertNil(GitHubReleases.failure(status: 200))
        XCTAssertEqual(GitHubReleases.failure(status: 404), "No release has been published yet.")
        XCTAssertEqual(GitHubReleases.failure(status: 503), "GitHub answered with status 503.")
    }
}

final class UpdatePolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func testChecksAtMostOncePerDay() {
        XCTAssertTrue(UpdatePolicy.isCheckDue(lastCheck: nil, now: now))
        XCTAssertFalse(UpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        XCTAssertFalse(UpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(-24 * 3600), now: now))
        XCTAssertTrue(UpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(-24 * 3600 - 1), now: now))
        // The timer fires more often than the interval, so a missed check is caught up within hours.
        XCTAssertLessThan(UpdatePolicy.timerInterval, UpdatePolicy.checkInterval)
    }

    func testAutomaticInstallWaitsForIdleAndApp() {
        XCTAssertFalse(UpdatePolicy.shouldInstallAutomatically(idleSeconds: 599, appAllows: true))
        XCTAssertTrue(UpdatePolicy.shouldInstallAutomatically(idleSeconds: 600, appAllows: true))
        XCTAssertFalse(UpdatePolicy.shouldInstallAutomatically(idleSeconds: 3600, appAllows: false))
    }

    func testNotifiesOncePerVersionForAutomaticChecks() throws {
        let v = try XCTUnwrap(AppVersion("0.3.1"))
        XCTAssertTrue(UpdatePolicy.shouldNotify(about: v, lastNotified: nil, userInitiated: false))
        XCTAssertTrue(UpdatePolicy.shouldNotify(about: v, lastNotified: "0.3.0", userInitiated: false))
        XCTAssertFalse(UpdatePolicy.shouldNotify(about: v, lastNotified: "0.3.1", userInitiated: false))
        XCTAssertFalse(UpdatePolicy.shouldNotify(about: v, lastNotified: nil, userInitiated: true))
    }

    func release(_ version: String, prerelease: Bool? = nil) -> Release {
        let v = AppVersion(version)!
        return Release(version: v, zipURL: URL(string: "https://example.com/Snapgrid-\(version).zip")!,
                       notes: "", isPrerelease: prerelease ?? v.isPrerelease)
    }

    func testOnlyThePickedNewerDownloadIsInstalled() throws {
        let current = try XCTUnwrap(AppVersion("0.2.3"))
        let next = release("0.3.0")
        XCTAssertTrue(UpdatePolicy.accepts(bundleVersion: "0.3.0", for: next, current: current))
        XCTAssertFalse(UpdatePolicy.accepts(bundleVersion: "0.3.1", for: next, current: current), "zip doesn't match its release")
        XCTAssertFalse(UpdatePolicy.accepts(bundleVersion: nil, for: next, current: current))
        XCTAssertFalse(UpdatePolicy.accepts(bundleVersion: "garbage", for: next, current: current))
        XCTAssertFalse(UpdatePolicy.accepts(bundleVersion: "0.2.2", for: release("0.2.2"), current: current))
        XCTAssertFalse(UpdatePolicy.accepts(bundleVersion: "0.2.3", for: release("0.2.3"), current: current))
    }

    func testSwitchingBackToStableMayDowngrade() throws {
        let beta = try XCTUnwrap(AppVersion("0.4.0-beta.2"))
        XCTAssertTrue(UpdatePolicy.accepts(bundleVersion: "0.3.1", for: release("0.3.1"), current: beta, allowDowngrade: true))
        XCTAssertFalse(UpdatePolicy.accepts(bundleVersion: "0.3.1", for: release("0.3.1"), current: beta))
        XCTAssertFalse(UpdatePolicy.accepts(bundleVersion: "0.4.0-beta.1", for: release("0.4.0-beta.1"), current: beta,
                                            allowDowngrade: true), "a downgrade only goes to a stable release")
    }

    let releases = ["0.3.0", "0.3.1", "0.4.0-beta.1", "0.4.0-beta.2"]

    func testStableChannelIgnoresBetas() throws {
        let list = releases.map { release($0) }
        XCTAssertEqual(UpdatePolicy.update(from: list, channel: .stable, current: AppVersion("0.3.0")!)?.version.description, "0.3.1")
        XCTAssertNil(UpdatePolicy.update(from: list, channel: .stable, current: AppVersion("0.3.1")!))
        // Marked as pre-release on GitHub even without a -beta suffix.
        XCTAssertNil(UpdatePolicy.update(from: [release("0.5.0", prerelease: true)], channel: .stable, current: AppVersion("0.3.1")!))
    }

    func testBetaChannelGetsTheNewestOfBoth() throws {
        let list = releases.map { release($0) }
        XCTAssertEqual(UpdatePolicy.update(from: list, channel: .beta, current: AppVersion("0.3.1")!)?.version.description, "0.4.0-beta.2")
        XCTAssertEqual(UpdatePolicy.update(from: list + [release("0.4.0")], channel: .beta,
                                           current: AppVersion("0.4.0-beta.2")!)?.version.description, "0.4.0")
        XCTAssertNil(UpdatePolicy.update(from: list, channel: .beta, current: AppVersion("0.4.0-beta.2")!))
    }

    func testLeavingBetaWaitsForStableButOffersSwitchingBack() throws {
        let list = releases.map { release($0) }
        let beta = AppVersion("0.4.0-beta.2")!
        XCTAssertNil(UpdatePolicy.update(from: list, channel: .stable, current: beta))
        XCTAssertEqual(UpdatePolicy.stableFallback(from: list, channel: .stable, current: beta)?.version.description, "0.3.1")
        // Once 0.4.0 is out, the normal update leads back to stable; no switch-back offer needed.
        XCTAssertEqual(UpdatePolicy.update(from: list + [release("0.4.0")], channel: .stable, current: beta)?.version.description, "0.4.0")
        XCTAssertNil(UpdatePolicy.stableFallback(from: list + [release("0.4.0")], channel: .stable, current: beta))
        XCTAssertNil(UpdatePolicy.stableFallback(from: list, channel: .beta, current: beta))
        XCTAssertNil(UpdatePolicy.stableFallback(from: list, channel: .stable, current: AppVersion("0.3.1")!))
    }

    func testParsesReleaseList() throws {
        let json = """
        [{"tag_name": "v0.4.0-beta.1", "prerelease": true, "draft": false,
          "assets": [{"name": "Snapgrid-0.4.0-beta.1.zip", "browser_download_url": "https://example.com/b.zip"}]},
         {"tag_name": "v0.5.0", "draft": true,
          "assets": [{"name": "Snapgrid-0.5.0.zip", "browser_download_url": "https://example.com/d.zip"}]},
         {"tag_name": "v0.3.1", "prerelease": false, "assets": []},
         {"tag_name": "v0.3.0", "prerelease": false,
          "assets": [{"name": "Snapgrid-0.3.0.zip", "browser_download_url": "https://example.com/s.zip"}]}]
        """
        let list = try GitHubReleases.parseList(Data(json.utf8))
        XCTAssertEqual(list.map(\.version.description), ["0.4.0-beta.1", "0.3.0"], "drafts and releases without a zip are skipped")
        XCTAssertEqual(list.map(\.isPrerelease), [true, false])
        XCTAssertThrowsError(try GitHubReleases.parseList(Data("{}".utf8)))
        XCTAssertEqual(GitHubReleases.listURL(repo: "me/snapgrid")?.absoluteString,
                       "https://api.github.com/repos/me/snapgrid/releases?per_page=30")
    }

    func testSigningRequirementPinsIdentifierAndTeam() {
        let text = UpdatePolicy.signingRequirement(identifier: "dev.snapgrid.Snapgrid", team: "8NQ55VC3K2")
        XCTAssertEqual(text, #"anchor apple generic and identifier "dev.snapgrid.Snapgrid" and certificate leaf[subject.OU] = "8NQ55VC3K2""#)
        #if canImport(Security)
        var requirement: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(text as CFString, [], &requirement), errSecSuccess)
        #endif
    }
}
