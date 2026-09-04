import XCTest
@testable import BakoApp

final class RecoveryEngineTests: XCTestCase {
    func testCompletesMigrationFromStagedCentralTemporaryItem() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.makeSkill(at: fixture.temporary)
        let fingerprint = try Fingerprinter.fingerprint(of: fixture.temporary)
        try fixture.writeJournal(phase: .sourceStaged, fingerprint: fingerprint)

        let result = await RecoveryEngine(root: fixture.root).recover()

        XCTAssertEqual(result.completed, 1)
        XCTAssertEqual(result.failures, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.target.appendingPathComponent("SKILL.md").path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: fixture.source.path), fixture.target.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.journal.path))
    }

    func testRollsBackDuplicateWhenCentralTargetDisappeared() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.makeSkill(at: fixture.backup)
        let fingerprint = try Fingerprinter.fingerprint(of: fixture.backup)
        try fixture.writeJournal(phase: .sourceStaged, fingerprint: fingerprint, isDuplicate: true)

        let result = await RecoveryEngine(root: fixture.root).recover()

        XCTAssertEqual(result.rolledBack, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.appendingPathComponent("SKILL.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.backup.path))
    }

    func testPreparedTransactionWithUntouchedSourceIsDiscarded() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.makeSkill(at: fixture.source)
        let fingerprint = try Fingerprinter.fingerprint(of: fixture.source)
        try fixture.writeJournal(phase: .prepared, fingerprint: fingerprint)

        let result = await RecoveryEngine(root: fixture.root).recover()

        XCTAssertEqual(result.rolledBack, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.appendingPathComponent("SKILL.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.journal.path))
    }

    func testKeepsJournalWhenStagedContentFingerprintChanged() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.makeSkill(at: fixture.temporary)
        try fixture.writeJournal(phase: .sourceStaged, fingerprint: "not-the-current-fingerprint")

        let result = await RecoveryEngine(root: fixture.root).recover()

        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.temporary.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.journal.path))
    }

    func testCleansUpCommittedLegacyJournal() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.makeSkill(at: fixture.target)
        try FileManager.default.createSymbolicLink(at: fixture.source, withDestinationURL: fixture.target)
        let object: [String: String] = [
            "id": fixture.transactionID.uuidString,
            "source": fixture.source.path,
            "target": fixture.target.path,
            "state": "committed",
            "updatedAt": ISO8601DateFormatter().string(from: Date())
        ]
        try JSONSerialization.data(withJSONObject: object).write(to: fixture.journal)

        let result = await RecoveryEngine(root: fixture.root).recover()

        XCTAssertEqual(result.completed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.journal.path))
    }
}

private struct Fixture {
    let root: URL
    let transactionID = UUID()

    var source: URL { root.appendingPathComponent("origin/example") }
    var target: URL { root.appendingPathComponent("Skills/skill-id") }
    var temporary: URL { root.appendingPathComponent("Skills/.skill-id.tmp") }
    var backup: URL { root.appendingPathComponent("origin/.example.backup") }
    var journal: URL { root.appendingPathComponent("State/transactions/\(transactionID.uuidString).json") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BakoRecovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("origin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Skills"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("State/transactions"), withIntermediateDirectories: true)
    }

    func makeSkill(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("---\nname: example\ndescription: Example\n---\n".utf8)
            .write(to: url.appendingPathComponent("SKILL.md"))
    }

    func writeJournal(
        phase: MigrationTransaction.Phase,
        fingerprint: String,
        isDuplicate: Bool = false
    ) throws {
        try TransactionJournal.write(.init(
            id: transactionID,
            sourcePath: source.path,
            targetPath: target.path,
            temporaryPath: temporary.path,
            backupPath: backup.path,
            expectedFingerprint: fingerprint,
            isDuplicate: isDuplicate,
            phase: phase,
            updatedAt: Date()
        ), to: journal)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
