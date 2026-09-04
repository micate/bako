import Foundation

struct SkillCandidate: Identifiable, Hashable {
    let id: UUID
    var url: URL
    var name: String
    var summary: String
    var kind: SkillEntryKind
    var fingerprint: String?
    var health: SkillHealth
    var linkDestination: String?
}

struct SkillScanner {
    var fileManager: FileManager = .default

    func scan(source: URL, kinds: Set<SkillEntryKind>) -> [Result<SkillCandidate, Error>] {
        let candidates: [URL]
        if fileManager.fileExists(atPath: source.appendingPathComponent("SKILL.md").path) {
            candidates = [source]
        } else {
            candidates = (try? fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        }

        return candidates.compactMap { url in
            let isFlat = url.pathExtension.lowercased() == "md"
            if isFlat && !kinds.contains(.flatMarkdown) { return nil }
            if !isFlat && !kinds.contains(.directoryBundle) { return nil }
            if !isFlat && !fileManager.fileExists(atPath: url.appendingPathComponent("SKILL.md").path) {
                return nil
            }
            return Result { try inspect(url, kind: isFlat ? .flatMarkdown : .directoryBundle) }
        }
    }

    private func inspect(_ url: URL, kind: SkillEntryKind) throws -> SkillCandidate {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let isLink = attributes[.type] as? FileAttributeType == .typeSymbolicLink
        var health: SkillHealth = .unmounted
        var destination: String?
        var fingerprint: String?

        if isLink {
            destination = try fileManager.destinationOfSymbolicLink(atPath: url.path)
            let resolved = url.deletingLastPathComponent().appendingPathComponent(destination!).standardizedFileURL
            health = fileManager.fileExists(atPath: resolved.path) ? .externalLink : .brokenLink
        } else {
            fingerprint = try Fingerprinter.fingerprint(of: url, fileManager: fileManager)
        }

        let metadataURL = kind == .directoryBundle ? url.appendingPathComponent("SKILL.md") : url
        let metadata = SkillMetadataParser.parse((try? String(contentsOf: metadataURL, encoding: .utf8)) ?? "")
        return SkillCandidate(
            id: UUID(), url: url,
            name: metadata.name ?? url.deletingPathExtension().lastPathComponent,
            summary: metadata.description ?? "",
            kind: kind, fingerprint: fingerprint, health: health, linkDestination: destination
        )
    }

}
