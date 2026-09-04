import Foundation
import SQLite3

struct PersistedState: Codable {
    var skills: [Skill] = []
    var groups: [SkillGroup] = []
    var activity: [ActivityRecord] = []
    var scanSources: [ScanSource] = []
    var disabledAgentIDs: Set<String> = []

    private enum CodingKeys: String, CodingKey { case skills, groups, activity, scanSources, disabledAgentIDs }

    init(
        skills: [Skill] = [], groups: [SkillGroup] = [], activity: [ActivityRecord] = [],
        scanSources: [ScanSource] = [], disabledAgentIDs: Set<String> = []
    ) {
        self.skills = skills
        self.groups = groups
        self.activity = activity
        self.scanSources = scanSources
        self.disabledAgentIDs = disabledAgentIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skills = try container.decodeIfPresent([Skill].self, forKey: .skills) ?? []
        groups = try container.decodeIfPresent([SkillGroup].self, forKey: .groups) ?? []
        activity = try container.decodeIfPresent([ActivityRecord].self, forKey: .activity) ?? []
        scanSources = try container.decodeIfPresent([ScanSource].self, forKey: .scanSources) ?? []
        disabledAgentIDs = try container.decodeIfPresent(Set<String>.self, forKey: .disabledAgentIDs) ?? []
    }
}

actor StateStore {
    private let databaseURL: URL
    private let legacyStateURL: URL

    init(root: URL) {
        let stateDirectory = root.appendingPathComponent("State", isDirectory: true)
        databaseURL = stateDirectory.appendingPathComponent("bako.sqlite")
        legacyStateURL = stateDirectory.appendingPathComponent("catalog.json")
    }

    func load() throws -> PersistedState {
        try withDatabase { database in
            if let data = try readPayload(from: database) {
                return try decode(data)
            }

            let migrated: PersistedState
            if FileManager.default.fileExists(atPath: legacyStateURL.path) {
                migrated = try decode(Data(contentsOf: legacyStateURL))
            } else {
                migrated = PersistedState()
            }
            try write(migrated, to: database)
            return migrated
        }
    }

    func save(_ state: PersistedState) throws {
        try withDatabase { database in try write(state, to: database) }
    }

    func journalMode() throws -> String {
        try withDatabase { database in
            var statement: OpaquePointer?
            try prepare("PRAGMA journal_mode", database: database, statement: &statement)
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW,
                  let value = sqlite3_column_text(statement, 0) else {
                throw StateStoreError.sqlite(message(for: database))
            }
            return String(cString: value)
        }
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database else {
            let detail = database.map(message(for:)) ?? L10n.string("error.database.open")
            if let database { sqlite3_close(database) }
            throw StateStoreError.sqlite(detail)
        }
        defer { sqlite3_close(database) }

        try execute("PRAGMA journal_mode=WAL", database: database)
        try execute("PRAGMA synchronous=FULL", database: database)
        try execute("PRAGMA busy_timeout=5000", database: database)
        try execute("""
            CREATE TABLE IF NOT EXISTS app_state (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                payload BLOB NOT NULL,
                updated_at TEXT NOT NULL
            )
            """, database: database)
        try execute("PRAGMA user_version=1", database: database)
        return try body(database)
    }

    private func readPayload(from database: OpaquePointer) throws -> Data? {
        var statement: OpaquePointer?
        try prepare("SELECT payload FROM app_state WHERE id = 1", database: database, statement: &statement)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw StateStoreError.sqlite(message(for: database)) }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    private func write(_ state: PersistedState, to database: OpaquePointer) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)

        try execute("BEGIN IMMEDIATE", database: database)
        do {
            var statement: OpaquePointer?
            try prepare(
                "INSERT INTO app_state(id, payload, updated_at) VALUES(1, ?, ?) " +
                "ON CONFLICT(id) DO UPDATE SET payload=excluded.payload, updated_at=excluded.updated_at",
                database: database,
                statement: &statement
            )
            defer { sqlite3_finalize(statement) }
            let bindResult = data.withUnsafeBytes { buffer in
                sqlite3_bind_blob(statement, 1, buffer.baseAddress, Int32(buffer.count), sqliteTransient)
            }
            guard bindResult == SQLITE_OK else { throw StateStoreError.sqlite(message(for: database)) }
            let timestamp = ISO8601DateFormatter().string(from: Date())
            guard sqlite3_bind_text(statement, 2, timestamp, -1, sqliteTransient) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_DONE else {
                throw StateStoreError.sqlite(message(for: database))
            }
            try execute("COMMIT", database: database)
        } catch {
            try? execute("ROLLBACK", database: database)
            throw error
        }
    }

    private func decode(_ data: Data) throws -> PersistedState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PersistedState.self, from: data)
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let detail = errorPointer.map { String(cString: $0) } ?? message(for: database)
            sqlite3_free(errorPointer)
            throw StateStoreError.sqlite(detail)
        }
    }

    private func prepare(_ sql: String, database: OpaquePointer, statement: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StateStoreError.sqlite(message(for: database))
        }
    }

    private func message(for database: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(database))
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum StateStoreError: LocalizedError {
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .sqlite(let detail): return L10n.string("error.database.state", detail)
        }
    }
}
