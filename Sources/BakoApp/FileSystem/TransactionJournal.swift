import Foundation

struct MigrationTransaction: Codable, Equatable {
    enum Phase: String, Codable {
        case prepared
        case sourceStaged
        case centralCommitted
        case linkCommitted
        case committed
    }

    let id: UUID
    let sourcePath: String
    let targetPath: String
    let temporaryPath: String
    let backupPath: String
    let expectedFingerprint: String
    let isDuplicate: Bool
    var usesCopy: Bool? = nil
    var phase: Phase
    var updatedAt: Date
}

enum TransactionJournal {
    static func read(from url: URL) throws -> MigrationTransaction {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url)
        if let transaction = try? decoder.decode(MigrationTransaction.self, from: data) {
            return transaction
        }

        // The first implementation only recorded these five fields. Reading it keeps
        // already-committed migrations from becoming permanent recovery warnings.
        let legacy = try decoder.decode(LegacyTransaction.self, from: data)
        let source = URL(fileURLWithPath: legacy.source)
        let target = URL(fileURLWithPath: legacy.target)
        return MigrationTransaction(
            id: legacy.id,
            sourcePath: source.path,
            targetPath: target.path,
            temporaryPath: target.deletingLastPathComponent()
                .appendingPathComponent(".\(target.lastPathComponent).tmp").path,
            backupPath: source.deletingLastPathComponent()
                .appendingPathComponent(".\(source.lastPathComponent).bako-\(legacy.id.uuidString).tmp").path,
            expectedFingerprint: "",
            isDuplicate: false,
            usesCopy: nil,
            phase: legacy.state == "committed" ? .committed : .prepared,
            updatedAt: legacy.updatedAt
        )
    }

    static func write(_ transaction: MigrationTransaction, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(transaction).write(to: url, options: .atomic)
    }

    private struct LegacyTransaction: Codable {
        let id: UUID
        let source: String
        let target: String
        let state: String
        let updatedAt: Date
    }
}
