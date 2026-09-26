import XCTest
@testable import SnapgridCore

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
    }
}
