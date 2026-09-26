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

    func testOnlyNewerDownloadsAreInstalled() throws {
        let current = try XCTUnwrap(AppVersion("0.2.3"))
        XCTAssertTrue(UpdatePolicy.isNewer(bundleVersion: "0.3.0", than: current))
        XCTAssertFalse(UpdatePolicy.isNewer(bundleVersion: "0.2.3", than: current))
        XCTAssertFalse(UpdatePolicy.isNewer(bundleVersion: "0.2.2", than: current))
        XCTAssertFalse(UpdatePolicy.isNewer(bundleVersion: nil, than: current))
        XCTAssertFalse(UpdatePolicy.isNewer(bundleVersion: "garbage", than: current))
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
