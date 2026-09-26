import XCTest
@testable import SnapgridCore

final class CloudSyncTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("cloudsync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("drive"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    func testEnableOnTwoMacsThenDisable() throws {
        let sync = CloudSync(driveRoot: root.appendingPathComponent("drive"))
        XCTAssertTrue(sync.isAvailable)
        let macA = root.appendingPathComponent("a/config.toml")
        let macB = root.appendingPathComponent("b/config.toml")
        try FileManager.default.createDirectory(at: macA.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: macB.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "A".write(to: macA, atomically: true, encoding: .utf8)
        try "B".write(to: macB, atomically: true, encoding: .utf8)

        try sync.enable(for: macA, useCloudCopy: true)
        XCTAssertTrue(sync.isEnabled(for: macA))
        XCTAssertEqual(read(sync.configURL), "A")
        XCTAssertEqual(read(macA), "A")

        try sync.enable(for: macB, useCloudCopy: true)
        XCTAssertEqual(read(macB), "A")
        XCTAssertEqual(read(macB.appendingPathExtension("bak")), "B")

        try sync.disable(for: macA)
        XCTAssertFalse(sync.isEnabled(for: macA))
        XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: macA.path))
        XCTAssertEqual(read(macA), "A")
        XCTAssertTrue(sync.hasCloudConfig)
    }

    func testEnableReplacingCloudCopyKeepsBackup() throws {
        let sync = CloudSync(driveRoot: root.appendingPathComponent("drive"))
        try FileManager.default.createDirectory(at: sync.configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "cloud".write(to: sync.configURL, atomically: true, encoding: .utf8)
        let local = root.appendingPathComponent("config.toml")
        try "local".write(to: local, atomically: true, encoding: .utf8)

        try sync.enable(for: local, useCloudCopy: false)
        XCTAssertEqual(read(local), "local")
        XCTAssertEqual(read(sync.configURL.appendingPathExtension("bak")), "cloud")
    }
}
