import Foundation
import XCTest
@testable import BakoApp

final class SkillDeletionEngineTests: XCTestCase {
    func testDeleteRemovesCentralSkillAndOnlyMatchingLinks() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let central = root.appendingPathComponent("Skills/skill-id", isDirectory: true)
        let links = root.appendingPathComponent("agent-skills", isDirectory: true)
        try FileManager.default.createDirectory(at: central, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: links, withIntermediateDirectories: true)
        try "test".write(to: central.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let matchingLink = links.appendingPathComponent("matching")
        try FileManager.default.createSymbolicLink(at: matchingLink, withDestinationURL: central)
        let regularFile = links.appendingPathComponent("regular")
        try "keep".write(to: regularFile, atomically: true, encoding: .utf8)
        let skill = Skill(
            id: UUID(), name: "Test", summary: "", kind: .directoryBundle,
            fingerprint: "hash", centralPath: central.path,
            origins: [.init(id: UUID(), agentID: nil, path: matchingLink.path, discoveredAt: Date())],
            health: .managed
        )

        let result = await SkillDeletionEngine(root: root).delete(skill, linkRoots: [links])

        XCTAssertTrue(result.deleted)
        XCTAssertEqual(result.removedLinks, 1)
        XCTAssertTrue(result.failures.isEmpty, "\(result.failures)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: central.path))
        XCTAssertNil(try? FileManager.default.attributesOfItem(atPath: matchingLink.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: regularFile.path))
    }

    func testDeleteRejectsPathOutsideManagedStorage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let skill = Skill(
            id: UUID(), name: "Outside", summary: "", kind: .directoryBundle,
            fingerprint: "hash", centralPath: outside.path, origins: [], health: .managed
        )

        let result = await SkillDeletionEngine(root: root).delete(skill)

        XCTAssertFalse(result.deleted)
        XCTAssertFalse(result.failures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testDeleteRejectsManagedPathThatTraversesSymlinkOutsideStorage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let skillsRoot = root.appendingPathComponent("Skills", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        let outsideSkill = outside.appendingPathComponent("skill", isDirectory: true)
        try FileManager.default.createDirectory(at: skillsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideSkill, withIntermediateDirectories: true)
        let escape = skillsRoot.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: outside)
        let skill = Skill(
            id: UUID(), name: "Outside", summary: "", kind: .directoryBundle,
            fingerprint: "hash", centralPath: escape.appendingPathComponent("skill").path,
            origins: [], health: .managed
        )

        let result = await SkillDeletionEngine(root: root).delete(skill)

        XCTAssertFalse(result.deleted)
        XCTAssertFalse(result.failures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideSkill.path))
    }
}
