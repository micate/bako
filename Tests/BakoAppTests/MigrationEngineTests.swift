import XCTest
@testable import BakoApp

final class MigrationEngineTests: XCTestCase {
    func testCopyMigrationVerifiesThenReplacesSourceWithLink() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BakoMigration-\(UUID().uuidString)")
        let source = root.appendingPathComponent("external/example")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("---\nname: example\ndescription: Example\n---\nbody".utf8)
            .write(to: source.appendingPathComponent("SKILL.md"))
        defer { try? FileManager.default.removeItem(at: root) }
        let fingerprint = try Fingerprinter.fingerprint(of: source)
        let candidate = SkillCandidate(
            id: UUID(), url: source, name: "example", summary: "Example",
            kind: .directoryBundle, fingerprint: fingerprint, health: .unmounted,
            linkDestination: nil
        )

        let outcome = try await MigrationEngine(root: root, forceCopy: true).migrate(candidate, existing: [])

        XCTAssertEqual(try Fingerprinter.fingerprint(of: outcome.centralURL), fingerprint)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: source.path), outcome.centralURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("SKILL.md").path))
    }

    func testRecoveryCompletesCopyInterruptedAfterCentralCommit() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent("BakoCopyRecovery-\(UUID().uuidString)")
        let source = fixtureRoot.appendingPathComponent("external/example")
        let target = fixtureRoot.appendingPathComponent("Skills/skill-id")
        let temporary = fixtureRoot.appendingPathComponent("Skills/.skill-id.tmp")
        let backup = fixtureRoot.appendingPathComponent("external/.example.backup")
        let transactionID = UUID()
        let journal = fixtureRoot.appendingPathComponent("State/transactions/\(transactionID.uuidString).json")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        let content = Data("skill-content".utf8)
        try content.write(to: source.appendingPathComponent("SKILL.md"))
        try content.write(to: target.appendingPathComponent("SKILL.md"))
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let fingerprint = try Fingerprinter.fingerprint(of: source)
        try TransactionJournal.write(.init(
            id: transactionID, sourcePath: source.path, targetPath: target.path,
            temporaryPath: temporary.path, backupPath: backup.path,
            expectedFingerprint: fingerprint, isDuplicate: false, usesCopy: true,
            phase: .centralCommitted, updatedAt: Date()
        ), to: journal)

        let result = await RecoveryEngine(root: fixtureRoot).recover()

        XCTAssertEqual(result.completed, 1)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: source.path), target.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    }
}
