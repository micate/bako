import XCTest
@testable import BakoApp

final class SkillRestoreEngineTests: XCTestCase {
    func testMovesSkillAndRedirectsKnownAgentLinks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BakoRestore-\(UUID().uuidString)")
        let central = root.appendingPathComponent("central/skill-id")
        let sharedLink = root.appendingPathComponent("shared/example")
        let agentLink = root.appendingPathComponent("agent/example")
        try FileManager.default.createDirectory(at: central, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sharedLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agentLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("skill".utf8).write(to: central.appendingPathComponent("SKILL.md"))
        try FileManager.default.createSymbolicLink(at: sharedLink, withDestinationURL: central)
        try FileManager.default.createSymbolicLink(at: agentLink, withDestinationURL: central)
        defer { try? FileManager.default.removeItem(at: root) }
        let skill = Skill(
            id: UUID(), name: "example", summary: "", kind: .directoryBundle,
            fingerprint: "hash", centralPath: central.path,
            origins: [
                .init(id: UUID(), agentID: nil, path: sharedLink.path, discoveredAt: Date())
            ], health: .mounted
        )

        let result = await SkillRestoreEngine().restore(
            [skill],
            to: sharedLink.deletingLastPathComponent(),
            linkRoots: [agentLink.deletingLastPathComponent()]
        )

        XCTAssertEqual(result.restoredSkillIDs, [skill.id])
        XCTAssertEqual(result.relinked, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sharedLink.appendingPathComponent("SKILL.md").path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: agentLink.path), sharedLink.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: central.path))
    }

    func testOccupiedDestinationLeavesCentralSkillAndLinksUntouched() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BakoRestore-\(UUID().uuidString)")
        let central = root.appendingPathComponent("central/skill-id")
        let destination = root.appendingPathComponent("shared/example")
        let agentLink = root.appendingPathComponent("agent/example")
        try FileManager.default.createDirectory(at: central, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agentLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("central".utf8).write(to: central.appendingPathComponent("SKILL.md"))
        try Data("user".utf8).write(to: destination.appendingPathComponent("SKILL.md"))
        try FileManager.default.createSymbolicLink(at: agentLink, withDestinationURL: central)
        defer { try? FileManager.default.removeItem(at: root) }
        let skill = Skill(
            id: UUID(), name: "example", summary: "", kind: .directoryBundle,
            fingerprint: "hash", centralPath: central.path,
            origins: [.init(id: UUID(), agentID: "codex", path: agentLink.path, discoveredAt: Date())],
            health: .mounted
        )

        let result = await SkillRestoreEngine().restore([skill], to: destination.deletingLastPathComponent())

        XCTAssertTrue(result.restoredSkillIDs.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: central.appendingPathComponent("SKILL.md").path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: agentLink.path), central.path)
    }

    func testExternalAgentLinkIsNotChanged() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BakoRestore-\(UUID().uuidString)")
        let central = root.appendingPathComponent("central/skill-id")
        let external = root.appendingPathComponent("external/example")
        let externalLink = root.appendingPathComponent("agent/external")
        try FileManager.default.createDirectory(at: central, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("central".utf8).write(to: central.appendingPathComponent("SKILL.md"))
        try Data("external".utf8).write(to: external.appendingPathComponent("SKILL.md"))
        try FileManager.default.createSymbolicLink(at: externalLink, withDestinationURL: external)
        defer { try? FileManager.default.removeItem(at: root) }
        let skill = Skill(
            id: UUID(), name: "example", summary: "", kind: .directoryBundle,
            fingerprint: "hash", centralPath: central.path, origins: [], health: .mounted
        )

        let result = await SkillRestoreEngine().restore(
            [skill], to: root.appendingPathComponent("shared"),
            linkRoots: [externalLink.deletingLastPathComponent()]
        )

        XCTAssertEqual(result.restoredSkillIDs, [skill.id])
        XCTAssertEqual(result.relinked, 0)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: externalLink.path), external.path)
    }
}
