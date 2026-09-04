import CryptoKit
import Foundation

enum FingerprintError: Error {
    case unsupportedEntry(URL)
}

enum Fingerprinter {
    static func fingerprint(of root: URL, fileManager: FileManager = .default) throws -> String {
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        if values.isRegularFile == true || values.isSymbolicLink == true {
            return try digest(entries: [root], relativeTo: root.deletingLastPathComponent(), fileManager: fileManager)
        }
        guard values.isDirectory == true else { throw FingerprintError.unsupportedEntry(root) }

        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        let entries = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        ).flatMap { entry -> [URL] in
            let itemValues = try entry.resourceValues(forKeys: Set(keys))
            if itemValues.isSymbolicLink == true { return [entry] }
            if itemValues.isDirectory == true {
                guard let enumerator = fileManager.enumerator(
                    at: entry,
                    includingPropertiesForKeys: keys,
                    options: [],
                    errorHandler: { _, _ in false }
                ) else { return [entry] }
                return [entry] + enumerator.compactMap { $0 as? URL }
            }
            return [entry]
        }
        return try digest(entries: entries, relativeTo: root, fileManager: fileManager)
    }

    private static func digest(entries: [URL], relativeTo root: URL, fileManager: FileManager) throws -> String {
        var hasher = SHA256()
        for entry in entries.sorted(by: { relativePath($0, root: root) < relativePath($1, root: root) }) {
            let path = relativePath(entry, root: root)
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            let kind: UInt8
            let payload: Data
            if values.isSymbolicLink == true {
                kind = 2
                payload = Data(try fileManager.destinationOfSymbolicLink(atPath: entry.path).utf8)
            } else if values.isDirectory == true {
                kind = 1
                payload = Data()
            } else if values.isRegularFile == true {
                kind = 0
                payload = try Data(contentsOf: entry, options: [.mappedIfSafe])
            } else {
                kind = 3
                payload = Data()
            }
            hasher.update(data: Data(path.utf8))
            hasher.update(data: Data([0, kind, 0]))
            hasher.update(data: payload)
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func relativePath(_ url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }
}
