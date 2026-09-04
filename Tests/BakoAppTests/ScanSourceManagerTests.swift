import XCTest
@testable import BakoApp

final class ScanSourceManagerTests: XCTestCase {
    func testCreatesSourceAndDetectsGitWorkTree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BakoSource-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let repository = home.appendingPathComponent("project")
        let sourceURL = repository.appendingPathComponent("skills")
        let central = home.appendingPathComponent("Library/Bako")
        try FileManager.default.createDirectory(at: repository.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let resolver = PathResolver(homeDirectory: home, environment: [:])
        let source = try ScanSourceManager().makeSource(
            url: sourceURL, resolver: resolver, centralStore: central, existing: []
        )

        XCTAssertEqual(source.path, sourceURL.path)
        XCTAssertTrue(source.isInGitWorkTree)
        XCTAssertTrue(source.isEnabled)
        XCTAssertEqual(source.entryKinds, [.directoryBundle])
    }

    func testRejectsSourceOverlappingExistingEndpoint() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BakoSource-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let endpoint = home.appendingPathComponent(".agent/skills")
        let nested = endpoint.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(try ScanSourceManager().makeSource(
            url: nested,
            resolver: PathResolver(homeDirectory: home, environment: [:]),
            centralStore: home.appendingPathComponent("Library/Bako"),
            existing: [endpoint]
        ))
    }
}
