import Foundation

struct ScanSourceManager {
    var fileManager: FileManager = .default

    func makeSource(url: URL, resolver: PathResolver, centralStore: URL, existing: [URL]) throws -> ScanSource {
        let normalized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: normalized.path, isDirectory: &isDirectory), isDirectory.boolValue,
              fileManager.isReadableFile(atPath: normalized.path) else {
            throw PathResolverError.unsafePath(L10n.string("error.directory_unreadable", normalized.path))
        }
        try resolver.validateScanSource(normalized, centralStore: centralStore, existing: existing)
        let bookmark = try? normalized.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: [.fileResourceIdentifierKey],
            relativeTo: nil
        )
        return ScanSource(
            id: UUID(), name: normalized.lastPathComponent, path: normalized.path,
            bookmark: bookmark, entryKinds: [.directoryBundle], isEnabled: true,
            isInGitWorkTree: isInsideGitWorkTree(normalized), health: .available,
            lastScannedAt: nil, lastResult: nil
        )
    }

    func resolve(_ source: ScanSource) -> URL? {
        if let bookmark = source.bookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), !stale { return url.standardizedFileURL }
        }
        let fallback = URL(fileURLWithPath: source.path).standardizedFileURL
        return fileManager.fileExists(atPath: fallback.path) ? fallback : nil
    }

    func isInsideGitWorkTree(_ url: URL) -> Bool {
        var current = url.standardizedFileURL
        while current.path != "/" {
            if fileManager.fileExists(atPath: current.appendingPathComponent(".git").path) { return true }
            let parent = current.deletingLastPathComponent()
            if parent == current { break }
            current = parent
        }
        return false
    }
}
