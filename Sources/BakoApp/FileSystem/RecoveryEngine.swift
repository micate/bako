import Foundation

struct RecoveryResult: Equatable {
    var completed = 0
    var rolledBack = 0
    var failures: [String] = []
}

actor RecoveryEngine {
    private let fileManager: FileManager
    private let journalURL: URL

    init(root: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.journalURL = root.appendingPathComponent("State/transactions", isDirectory: true)
    }

    func recover() -> RecoveryResult {
        guard let journals = try? fileManager.contentsOfDirectory(
            at: journalURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return RecoveryResult() }

        var result = RecoveryResult()
        for journal in journals where journal.pathExtension == "json" {
            do {
                let transaction = try TransactionJournal.read(from: journal)
                switch try recover(transaction) {
                case .completed: result.completed += 1
                case .rolledBack: result.rolledBack += 1
                }
                try fileManager.removeItem(at: journal)
            } catch {
                result.failures.append("\(journal.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        return result
    }

    private enum Resolution { case completed, rolledBack }

    private func recover(_ transaction: MigrationTransaction) throws -> Resolution {
        let source = URL(fileURLWithPath: transaction.sourcePath)
        let target = URL(fileURLWithPath: transaction.targetPath)
        let temporary = URL(fileURLWithPath: transaction.temporaryPath)
        let backup = URL(fileURLWithPath: transaction.backupPath)

        if symlinkDestination(at: source) == target.standardizedFileURL,
           itemExists(at: target) {
            try removeIfPresent(temporary)
            try removeIfPresent(backup)
            return .completed
        }

        if !itemExists(at: target), itemExists(at: temporary) {
            let fingerprint = try Fingerprinter.fingerprint(of: temporary, fileManager: fileManager)
            guard fingerprint == transaction.expectedFingerprint else {
                throw MigrationError.sourceChanged
            }
            try fileManager.moveItem(at: temporary, to: target)
        }

        if transaction.usesCopy == true,
           itemExists(at: target),
           isRealItem(at: source) {
            let sourceFingerprint = try Fingerprinter.fingerprint(of: source, fileManager: fileManager)
            let targetFingerprint = try Fingerprinter.fingerprint(of: target, fileManager: fileManager)
            guard sourceFingerprint == transaction.expectedFingerprint,
                  targetFingerprint == transaction.expectedFingerprint else {
                throw MigrationError.sourceChanged
            }
            guard !itemExistsIncludingSymlink(at: backup) else {
                throw CocoaError(.fileWriteFileExists)
            }
            try fileManager.moveItem(at: source, to: backup)
            try createLinkAtomically(at: source, to: target, transactionID: transaction.id)
            try removeIfPresent(backup)
            try removeIfPresent(temporary)
            return .completed
        }

        if itemExists(at: target), !itemExistsIncludingSymlink(at: source) {
            try createLinkAtomically(at: source, to: target, transactionID: transaction.id)
            try removeIfPresent(backup)
            try removeIfPresent(temporary)
            return .completed
        }

        if !itemExists(at: target), itemExists(at: backup), !itemExistsIncludingSymlink(at: source) {
            try fileManager.moveItem(at: backup, to: source)
            try removeIfPresent(temporary)
            return .rolledBack
        }

        if transaction.phase == .prepared,
           itemExistsIncludingSymlink(at: source),
           !itemExists(at: temporary),
           !itemExists(at: backup) {
            return .rolledBack
        }

        throw CocoaError(.fileWriteUnknown, userInfo: [
            NSLocalizedDescriptionKey: L10n.string("error.recovery_inconsistent")
        ])
    }

    private func createLinkAtomically(at source: URL, to target: URL, transactionID: UUID) throws {
        let temporaryLink = source.deletingLastPathComponent()
            .appendingPathComponent(".\(source.lastPathComponent).bako-link-\(transactionID.uuidString).tmp")
        try removeIfPresent(temporaryLink)
        try fileManager.createSymbolicLink(at: temporaryLink, withDestinationURL: target)
        try fileManager.moveItem(at: temporaryLink, to: source)
    }

    private func itemExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    private func itemExistsIncludingSymlink(at url: URL) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)) != nil
    }

    private func symlinkDestination(at url: URL) -> URL? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeSymbolicLink,
              let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else { return nil }
        if destination.hasPrefix("/") { return URL(fileURLWithPath: destination).standardizedFileURL }
        return url.deletingLastPathComponent().appendingPathComponent(destination).standardizedFileURL
    }

    private func isRealItem(at url: URL) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return false }
        return attributes[.type] as? FileAttributeType != .typeSymbolicLink
    }

    private func removeIfPresent(_ url: URL) throws {
        if itemExistsIncludingSymlink(at: url) { try fileManager.removeItem(at: url) }
    }
}
