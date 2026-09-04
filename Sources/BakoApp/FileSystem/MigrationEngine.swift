import Foundation

enum MigrationError: LocalizedError {
    case sourceChanged
    case targetOccupied(String)
    case invalidCandidate

    var errorDescription: String? {
        switch self {
        case .sourceChanged: return L10n.string("error.source_changed")
        case .targetOccupied(let path): return L10n.string("error.target_occupied", path)
        case .invalidCandidate: return L10n.string("error.invalid_candidate")
        }
    }
}

actor MigrationEngine {
    struct Outcome {
        var skillID: UUID
        var centralURL: URL
        var deduplicated: Bool
    }

    private let fileManager: FileManager
    private let centralSkillsURL: URL
    private let journalURL: URL
    private let forceCopy: Bool

    init(root: URL, fileManager: FileManager = .default, forceCopy: Bool = false) {
        self.fileManager = fileManager
        self.centralSkillsURL = root.appendingPathComponent("Skills", isDirectory: true)
        self.journalURL = root.appendingPathComponent("State/transactions", isDirectory: true)
        self.forceCopy = forceCopy
    }

    func migrate(_ candidate: SkillCandidate, existing: [Skill]) throws -> Outcome {
        guard let expectedFingerprint = candidate.fingerprint else { throw MigrationError.invalidCandidate }
        guard try Fingerprinter.fingerprint(of: candidate.url, fileManager: fileManager) == expectedFingerprint else {
            throw MigrationError.sourceChanged
        }
        try fileManager.createDirectory(at: centralSkillsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: journalURL, withIntermediateDirectories: true)

        let duplicate = existing.first { $0.name == candidate.name && $0.fingerprint == expectedFingerprint }
        let skillID = duplicate?.id ?? UUID()
        let finalURL = duplicate.map { URL(fileURLWithPath: $0.centralPath) }
            ?? centralSkillsURL.appendingPathComponent(skillID.uuidString, isDirectory: candidate.kind == .directoryBundle)
        let transactionID = UUID()
        let journal = journalURL.appendingPathComponent("\(transactionID.uuidString).json")
        let sourceBackup = candidate.url.deletingLastPathComponent()
            .appendingPathComponent(".\(candidate.url.lastPathComponent).bako-\(transactionID.uuidString).tmp")
        let temporaryURL = centralSkillsURL.appendingPathComponent(".\(skillID.uuidString).tmp")
        let usesCopy = duplicate == nil && (forceCopy || areOnDifferentVolumes(candidate.url, centralSkillsURL))
        var transaction = MigrationTransaction(
            id: transactionID,
            sourcePath: candidate.url.path,
            targetPath: finalURL.path,
            temporaryPath: temporaryURL.path,
            backupPath: sourceBackup.path,
            expectedFingerprint: expectedFingerprint,
            isDuplicate: duplicate != nil,
            usesCopy: usesCopy,
            phase: .prepared,
            updatedAt: Date()
        )
        try TransactionJournal.write(transaction, to: journal)

        if duplicate == nil {
            if usesCopy {
                try fileManager.copyItem(at: candidate.url, to: temporaryURL)
            } else {
                try fileManager.moveItem(at: candidate.url, to: temporaryURL)
                try update(&transaction, phase: .sourceStaged, journal: journal)
            }
            let actual = try Fingerprinter.fingerprint(of: temporaryURL, fileManager: fileManager)
            guard actual == expectedFingerprint else {
                if usesCopy { try? fileManager.removeItem(at: temporaryURL) }
                else { try? fileManager.moveItem(at: temporaryURL, to: candidate.url) }
                throw MigrationError.sourceChanged
            }
            try fileManager.moveItem(at: temporaryURL, to: finalURL)
            try update(&transaction, phase: .centralCommitted, journal: journal)
            if usesCopy {
                try fileManager.moveItem(at: candidate.url, to: sourceBackup)
                try update(&transaction, phase: .sourceStaged, journal: journal)
            }
        } else {
            try fileManager.moveItem(at: candidate.url, to: sourceBackup)
            try update(&transaction, phase: .sourceStaged, journal: journal)
        }

        do {
            try fileManager.createSymbolicLink(at: candidate.url, withDestinationURL: finalURL)
        } catch {
            let rolledBack: Bool
            do {
                if duplicate == nil {
                    if usesCopy {
                        try fileManager.removeItem(at: finalURL)
                        try fileManager.moveItem(at: sourceBackup, to: candidate.url)
                    } else {
                        try fileManager.moveItem(at: finalURL, to: candidate.url)
                    }
                } else {
                    try fileManager.moveItem(at: sourceBackup, to: candidate.url)
                }
                rolledBack = true
            } catch {
                rolledBack = false
            }
            if rolledBack { try? fileManager.removeItem(at: journal) }
            throw error
        }
        try update(&transaction, phase: .linkCommitted, journal: journal)
        if duplicate != nil || usesCopy { try fileManager.removeItem(at: sourceBackup) }
        try update(&transaction, phase: .committed, journal: journal)
        return Outcome(skillID: skillID, centralURL: finalURL, deduplicated: duplicate != nil)
    }

    private func update(_ transaction: inout MigrationTransaction, phase: MigrationTransaction.Phase, journal: URL) throws {
        transaction.phase = phase
        transaction.updatedAt = Date()
        try TransactionJournal.write(transaction, to: journal)
    }

    private func areOnDifferentVolumes(_ source: URL, _ destinationDirectory: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let sourceValues = try? source.resourceValues(forKeys: keys),
              let destinationValues = try? destinationDirectory.resourceValues(forKeys: keys),
              let sourceIdentifier = sourceValues.volumeIdentifier,
              let destinationIdentifier = destinationValues.volumeIdentifier,
              let sourceVolume = sourceIdentifier as? NSObject,
              let destinationVolume = destinationIdentifier as? NSObject else { return false }
        return !sourceVolume.isEqual(destinationVolume)
    }
}
