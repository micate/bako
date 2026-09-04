import Foundation

struct SkillDeletionResult: Equatable {
    var deleted = false
    var removedLinks = 0
    var failures: [String] = []
}

actor SkillDeletionEngine {
    private let managedSkillsRoot: URL
    private let fileManager: FileManager

    init(root: URL, fileManager: FileManager = .default) {
        managedSkillsRoot = root.appendingPathComponent("Skills", isDirectory: true).standardizedFileURL
        self.fileManager = fileManager
    }

    func delete(_ skill: Skill, linkRoots: [URL] = []) -> SkillDeletionResult {
        var result = SkillDeletionResult()
        let centralURL = URL(fileURLWithPath: skill.centralPath).standardizedFileURL

        guard isManagedPath(centralURL) else {
            result.failures.append(L10n.string("error.skill_outside_storage", centralURL.path))
            return result
        }

        let links = knownLinks(for: skill, in: linkRoots, pointingTo: centralURL)
        var removedLinks: [URL] = []
        for link in links {
            do {
                try fileManager.removeItem(at: link)
                removedLinks.append(link)
            } catch {
                result.failures.append("\(link.path)：\(error.localizedDescription)")
                restoreLinks(removedLinks, to: centralURL, failures: &result.failures)
                return result
            }
        }

        do {
            if let attributes = try? fileManager.attributesOfItem(atPath: centralURL.path) {
                guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                    result.failures.append(L10n.string("error.skill_central_link", centralURL.path))
                    restoreLinks(removedLinks, to: centralURL, failures: &result.failures)
                    return result
                }
                try fileManager.removeItem(at: centralURL)
            }
            result.deleted = true
            result.removedLinks = removedLinks.count
        } catch {
            result.failures.append("\(skill.name)：\(error.localizedDescription)")
            restoreLinks(removedLinks, to: centralURL, failures: &result.failures)
        }
        return result
    }

    private func isManagedPath(_ url: URL) -> Bool {
        let resolvedRoot = managedSkillsRoot.resolvingSymlinksInPath().standardizedFileURL
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
        return resolvedURL.path.hasPrefix(rootPath) && resolvedURL.path != resolvedRoot.path
    }

    private func knownLinks(for skill: Skill, in linkRoots: [URL], pointingTo centralURL: URL) -> [URL] {
        var seen = Set<String>()
        var candidates = skill.origins.map { URL(fileURLWithPath: $0.path) }
        for root in linkRoots {
            let children = (try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            candidates.append(contentsOf: children)
        }
        return candidates.compactMap { url in
            let normalizedPath = url.standardizedFileURL.path
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard seen.insert(normalizedPath).inserted,
                  symbolicLinkDestination(at: url)?.path == centralURL.path else { return nil }
            return url
        }
    }

    private func symbolicLinkDestination(at url: URL) -> URL? {
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else { return nil }
        if destination.hasPrefix("/") { return URL(fileURLWithPath: destination).standardizedFileURL }
        return url.deletingLastPathComponent().appendingPathComponent(destination).standardizedFileURL
    }

    private func restoreLinks(_ links: [URL], to centralURL: URL, failures: inout [String]) {
        for link in links {
            do {
                try fileManager.createSymbolicLink(at: link, withDestinationURL: centralURL)
            } catch {
                failures.append("\(link.path)：\(error.localizedDescription)")
            }
        }
    }
}
