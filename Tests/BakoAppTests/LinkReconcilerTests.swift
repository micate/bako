import XCTest
@testable import BakoApp

final class LinkReconcilerTests: XCTestCase {
    func testCreatesDesiredAndRemovesOnlyCentralLinks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let central = root.appendingPathComponent("Skills/skill-id")
        let endpoint = root.appendingPathComponent("endpoint")
        let external = root.appendingPathComponent("external")
        try FileManager.default.createDirectory(at: central, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: endpoint, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let stale = endpoint.appendingPathComponent("stale")
        let foreign = endpoint.appendingPathComponent("foreign")
        try FileManager.default.createSymbolicLink(at: stale, withDestinationURL: central)
        try FileManager.default.createSymbolicLink(at: foreign, withDestinationURL: external)
        let skill = Skill(id: UUID(), name: "active", summary: "", kind: .directoryBundle,
                          fingerprint: "hash", centralPath: central.path, origins: [], health: .managed)
        let desired = DesiredMount(endpointID: "test", mountName: "active", skillID: skill.id, groupIDs: [])

        let result = await LinkReconciler(root: root).reconcile(
            desired: [desired], skills: [skill], endpoints: ["test": endpoint]
        )
        XCTAssertEqual(result.created, 1)
        XCTAssertEqual(result.removed, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreign.path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: endpoint.appendingPathComponent("active").path), central.path)
    }

    func testDoesNotOverwriteOccupiedTarget() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let central = root.appendingPathComponent("Skills/skill-id")
        let endpoint = root.appendingPathComponent("endpoint")
        try FileManager.default.createDirectory(at: central, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: endpoint, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: endpoint.appendingPathComponent("active"))
        defer { try? FileManager.default.removeItem(at: root) }
        let skill = Skill(id: UUID(), name: "active", summary: "", kind: .directoryBundle,
                          fingerprint: "hash", centralPath: central.path, origins: [], health: .managed)
        let desired = DesiredMount(endpointID: "test", mountName: "active", skillID: skill.id, groupIDs: [])

        let result = await LinkReconciler(root: root).reconcile(desired: [desired], skills: [skill], endpoints: ["test": endpoint])
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(String(data: try Data(contentsOf: endpoint.appendingPathComponent("active")), encoding: .utf8), "mine")
    }
}
