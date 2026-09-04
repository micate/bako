import Foundation

struct ReconcileResult: Equatable {
    var created = 0
    var removed = 0
    var unchanged = 0
    var failures: [String] = []
}

actor LinkReconciler {
    private let fileManager: FileManager
    private let centralSkillsURL: URL

    init(root: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.centralSkillsURL = root.appendingPathComponent("Skills", isDirectory: true).standardizedFileURL
    }

    func reconcile(desired: [DesiredMount], skills: [Skill], endpoints: [String: URL]) -> ReconcileResult {
        let skillByID = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0) })
        let desiredKeys = Set(desired.map { "\($0.endpointID)|\($0.mountName)" })
        var result = ReconcileResult()

        for mount in desired {
            guard let endpoint = endpoints[mount.endpointID], let skill = skillByID[mount.skillID] else { continue }
            do {
                try fileManager.createDirectory(at: endpoint, withIntermediateDirectories: true)
                let mountURL = endpoint.appendingPathComponent(mount.mountName)
                let expected = URL(fileURLWithPath: skill.centralPath).standardizedFileURL
                if let actual = resolvedSymlink(at: mountURL) {
                    if actual == expected { result.unchanged += 1 }
                    else { result.failures.append(L10n.string("error.target_occupied", mountURL.path)) }
                } else if fileManager.fileExists(atPath: mountURL.path) {
                    result.failures.append(L10n.string("error.target_occupied", mountURL.path))
                } else {
                    let temporary = endpoint.appendingPathComponent(".\(mount.mountName).bako-\(UUID().uuidString).tmp")
                    try fileManager.createSymbolicLink(at: temporary, withDestinationURL: expected)
                    try fileManager.moveItem(at: temporary, to: mountURL)
                    result.created += 1
                }
            } catch {
                result.failures.append(error.localizedDescription)
            }
        }

        for (endpointID, endpoint) in endpoints {
            guard let children = try? fileManager.contentsOfDirectory(at: endpoint, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { continue }
            for child in children {
                let key = "\(endpointID)|\(child.lastPathComponent)"
                guard !desiredKeys.contains(key), let target = resolvedSymlink(at: child), isInsideCentralStore(target) else { continue }
                do {
                    try fileManager.removeItem(at: child)
                    result.removed += 1
                } catch {
                    result.failures.append(error.localizedDescription)
                }
            }
        }
        return result
    }

    private func resolvedSymlink(at url: URL) -> URL? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeSymbolicLink,
              let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else { return nil }
        if destination.hasPrefix("/") { return URL(fileURLWithPath: destination).standardizedFileURL }
        return url.deletingLastPathComponent().appendingPathComponent(destination).standardizedFileURL
    }

    private func isInsideCentralStore(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let root = centralSkillsURL.path
        return path == root || path.hasPrefix(root + "/")
    }
}
