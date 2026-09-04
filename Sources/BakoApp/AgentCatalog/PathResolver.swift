import Foundation

enum PathResolverError: LocalizedError {
    case unresolvedVariable(String)
    case unsafePath(String)
    case overlappingPath(String)

    var errorDescription: String? {
        switch self {
        case .unresolvedVariable(let name): return L10n.string("error.unresolved_variable", name)
        case .unsafePath(let path): return L10n.string("error.unsafe_path", path)
        case .overlappingPath(let path): return L10n.string("error.overlapping_path", path)
        }
    }
}

struct PathResolver {
    var homeDirectory: URL
    var environment: [String: String]

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.environment = environment
    }

    func resolve(_ template: String) throws -> URL {
        var value = template
        if value == "~" || value.hasPrefix("~/") {
            value = homeDirectory.path + value.dropFirst()
        }

        let pattern = #"\$\{([A-Za-z_][A-Za-z0-9_]*)(:-([^}]+))?\}"#
        let regex = try NSRegularExpression(pattern: pattern)
        while let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) {
            guard
                let wholeRange = Range(match.range(at: 0), in: value),
                let nameRange = Range(match.range(at: 1), in: value)
            else { break }
            let name = String(value[nameRange])
            let fallback: String? = match.range(at: 3).location == NSNotFound
                ? nil
                : Range(match.range(at: 3), in: value).map { String(value[$0]) }
            let replacement = environment[name].flatMap { $0.isEmpty ? nil : $0 } ?? fallback
            guard let replacement else {
                throw PathResolverError.unresolvedVariable(name)
            }
            value.replaceSubrange(wholeRange, with: replacement)
            if value == "~" || value.hasPrefix("~/") {
                value = homeDirectory.path + value.dropFirst()
            }
        }
        return URL(fileURLWithPath: value).standardizedFileURL
    }

    func validateScanSource(_ url: URL, centralStore: URL, existing: [URL]) throws {
        let path = url.standardizedFileURL.path
        let home = homeDirectory.path
        guard path != "/", path != home, path.count > 1 else {
            throw PathResolverError.unsafePath(path)
        }
        let central = centralStore.standardizedFileURL.path
        guard path != central, !path.hasPrefix(central + "/") else {
            throw PathResolverError.unsafePath(path)
        }
        for other in existing.map(\.standardizedFileURL.path) {
            if path == other || path.hasPrefix(other + "/") || other.hasPrefix(path + "/") {
                throw PathResolverError.overlappingPath(path)
            }
        }
    }
}
