import Foundation

struct SkillRestoreResult: Equatable {
    var restoredSkillIDs: Set<UUID> = []
    var relinked = 0
    var failures: [String] = []
}

actor SkillRestoreEngine {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func restore(
        _ skills: [Skill],
        to destinationRoot: URL,
        linkRoots: [URL] = []
    ) -> SkillRestoreResult {
        var result = SkillRestoreResult()

        do {
            try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        } catch {
            result.failures.append(error.localizedDescription)
            return result
        }

        for skill in skills {
            do {
                let source = URL(fileURLWithPath: skill.centralPath).standardizedFileURL
                guard isRealItem(at: source) else {
                    throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: source.path])
                }

                let destination = destinationRoot
                    .appendingPathComponent(restoredName(for: skill), isDirectory: skill.kind == .directoryBundle)
                    .standardizedFileURL
                let destinationLinkTarget = symlinkDestination(at: destination)
                if itemExistsIncludingSymlink(at: destination), destinationLinkTarget?.path != source.path {
                    throw MigrationError.targetOccupied(destination.path)
                }

                let links = knownLinks(for: skill, in: linkRoots, pointingTo: source)
                    .filter { $0.standardizedFileURL.path != destination.path }
                var updatedLinks: [URL] = []
                do {
                    try moveSource(source, replacingLinkAt: destination, expectedTarget: destinationLinkTarget)
                    for link in links {
                        if try replaceLink(at: link, previouslyPointingTo: source, with: destination) {
                            updatedLinks.append(link)
                        }
                    }
                } catch {
                    for link in updatedLinks.reversed() {
                        _ = try? replaceLink(at: link, previouslyPointingTo: destination, with: source)
                    }
                    if isRealItem(at: destination), !itemExistsIncludingSymlink(at: source) {
                        try? fileManager.moveItem(at: destination, to: source)
                        if destinationLinkTarget?.path == source.path {
                            try? fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
                        }
                    }
                    throw error
                }
                result.relinked += updatedLinks.count
                result.restoredSkillIDs.insert(skill.id)
            } catch {
                result.failures.append("\(skill.name)：\(error.localizedDescription)")
            }
        }
        return result
    }

    private func restoredName(for skill: Skill) -> String {
        let proposedFallback = skill.kind == .flatMarkdown ? "\(skill.name).md" : skill.name
        let fallback = isSafeFilename(proposedFallback) ? proposedFallback : {
            skill.kind == .flatMarkdown ? "\(skill.id.uuidString).md" : skill.id.uuidString
        }()
        guard let originName = skill.origins.first.map({ URL(fileURLWithPath: $0.path).lastPathComponent }),
              isSafeFilename(originName) else { return fallback }
        if skill.kind == .flatMarkdown,
           URL(fileURLWithPath: originName).pathExtension.lowercased() != "md" {
            return fallback
        }
        return originName
    }

    private func isSafeFilename(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." &&
            !name.contains("/") && !name.contains(":") && !name.contains("\0")
    }

    private func knownLinks(for skill: Skill, in linkRoots: [URL], pointingTo source: URL) -> [URL] {
        var seen = Set<String>()
        var candidates = skill.origins.map { URL(fileURLWithPath: $0.path).standardizedFileURL }
        for root in linkRoots {
            let children = (try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            candidates.append(contentsOf: children)
        }
        return candidates.compactMap { url in
            guard seen.insert(url.path).inserted, symlinkDestination(at: url)?.path == source.path else { return nil }
            return url
        }
    }

    private func moveSource(_ source: URL, replacingLinkAt destination: URL, expectedTarget: URL?) throws {
        guard expectedTarget != nil else {
            try fileManager.moveItem(at: source, to: destination)
            return
        }

        let backup = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).bako-restore-\(UUID().uuidString).tmp")
        try fileManager.moveItem(at: destination, to: backup)
        do {
            try fileManager.moveItem(at: source, to: destination)
            try fileManager.removeItem(at: backup)
        } catch {
            if !itemExistsIncludingSymlink(at: destination), itemExistsIncludingSymlink(at: backup) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
    }

    @discardableResult
    private func replaceLink(at link: URL, previouslyPointingTo source: URL, with destination: URL) throws -> Bool {
        guard symlinkDestination(at: link)?.path == source.path else { return false }
        let temporary = link.deletingLastPathComponent()
            .appendingPathComponent(".\(link.lastPathComponent).bako-restore-link-\(UUID().uuidString).tmp")
        try fileManager.createSymbolicLink(at: temporary, withDestinationURL: destination)
        do {
            try fileManager.removeItem(at: link)
            try fileManager.moveItem(at: temporary, to: link)
        } catch {
            try? fileManager.removeItem(at: temporary)
            if !itemExistsIncludingSymlink(at: link) {
                try? fileManager.createSymbolicLink(at: link, withDestinationURL: source)
            }
            throw error
        }
        return true
    }

    private func symlinkDestination(at url: URL) -> URL? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeSymbolicLink,
              let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else { return nil }
        if destination.hasPrefix("/") { return URL(fileURLWithPath: destination).standardizedFileURL }
        return url.deletingLastPathComponent().appendingPathComponent(destination).standardizedFileURL
    }

    private func itemExistsIncludingSymlink(at url: URL) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)) != nil
    }

    private func isRealItem(at url: URL) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return false }
        return attributes[.type] as? FileAttributeType != .typeSymbolicLink
    }
}
