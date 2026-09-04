import XCTest
@testable import BakoApp

final class PathResolverTests: XCTestCase {
    func testResolvesHomeAndEnvironmentFallbacks() throws {
        let resolver = PathResolver(
            homeDirectory: URL(fileURLWithPath: "/tmp/bako-home"),
            environment: [:]
        )
        XCTAssertEqual(try resolver.resolve("~/.codex/skills").path, "/tmp/bako-home/.codex/skills")
        XCTAssertEqual(try resolver.resolve("${DSH_HOME:-~/.dsh}/skills").path, "/tmp/bako-home/.dsh/skills")
    }

    func testRejectsHomeAndNestedSources() throws {
        let resolver = PathResolver(homeDirectory: URL(fileURLWithPath: "/tmp/bako-home"), environment: [:])
        XCTAssertThrowsError(try resolver.validateScanSource(
            URL(fileURLWithPath: "/tmp/bako-home"),
            centralStore: URL(fileURLWithPath: "/tmp/bako-home/Library/Application Support/Bako"),
            existing: []
        ))
        XCTAssertThrowsError(try resolver.validateScanSource(
            URL(fileURLWithPath: "/tmp/bako-home/custom/nested"),
            centralStore: URL(fileURLWithPath: "/tmp/bako-home/Library/Application Support/Bako"),
            existing: [URL(fileURLWithPath: "/tmp/bako-home/custom")]
        ))
    }
}
