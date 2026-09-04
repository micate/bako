import XCTest
@testable import BakoApp

final class StateStoreTests: XCTestCase {
    func testLoadsLegacyStateWithoutScanSources() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BakoState-\(UUID().uuidString)")
        let stateURL = root.appendingPathComponent("State/catalog.json")
        let groupID = UUID()
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("""
            {"skills":[],"groups":[{"id":"\(groupID.uuidString)","name":"已导入 · OpenAI Codex","skillIDs":[],"targets":[],"isEnabled":true,"isSystem":true}],"activity":[]}
            """.utf8).write(to: stateURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let state = try await StateStore(root: root).load()

        XCTAssertEqual(state.scanSources, [])
        XCTAssertEqual(state.disabledAgentIDs, [])
        XCTAssertEqual(state.groups.first?.id, groupID)
        XCTAssertNil(state.groups.first?.sourceID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("State/bako.sqlite").path))
        let journalMode = try await StateStore(root: root).journalMode()
        XCTAssertEqual(journalMode.lowercased(), "wal")
    }

    func testRoundTripsStateThroughSQLite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BakoState-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(root: root)
        let activity = ActivityRecord(
            id: UUID(), date: Date(timeIntervalSince1970: 1_700_000_000),
            kind: .scan, title: "完成", detail: "SQLite", isError: false
        )

        try await store.save(.init(activity: [activity], disabledAgentIDs: ["codex"]))
        let loaded = try await store.load()
        let journalMode = try await store.journalMode()

        XCTAssertEqual(loaded.activity, [activity])
        XCTAssertEqual(loaded.disabledAgentIDs, ["codex"])
        XCTAssertEqual(journalMode.lowercased(), "wal")
    }
}
