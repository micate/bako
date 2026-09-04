import Foundation

enum MountPlanner {
    static func desiredMounts(
        groups: [SkillGroup],
        skills: [Skill],
        endpointsByAgent: [String: [String]],
        preferredVariants: [String: UUID] = [:]
    ) -> [DesiredMount] {
        let skillByID = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0) })
        var candidates: [String: [(skill: Skill, group: SkillGroup)]] = [:]

        for group in groups where group.isEnabled {
            for target in group.targets {
                let endpointIDs: [String]
                switch target {
                case .agent(let agentID): endpointIDs = endpointsByAgent[agentID] ?? []
                case .shared(let endpointID): endpointIDs = [endpointID]
                }
                for endpointID in endpointIDs {
                    for skillID in group.skillIDs {
                        guard let skill = skillByID[skillID] else { continue }
                        candidates["\(endpointID)|\(skill.name)", default: []].append((skill, group))
                    }
                }
            }
        }

        return candidates.compactMap { key, values in
            guard let separator = key.firstIndex(of: "|") else { return nil }
            let endpointID = String(key[..<separator])
            let name = String(key[key.index(after: separator)...])
            let preferenceKey = "\(endpointID)|\(name)"
            let preferredID = preferredVariants[preferenceKey]

            let selected = values.first(where: { $0.skill.id == preferredID })
                ?? values.sorted {
                    let left = $0.group.lastEnabledAt ?? .distantPast
                    let right = $1.group.lastEnabledAt ?? .distantPast
                    if left != right { return left > right }
                    return $0.skill.id.uuidString < $1.skill.id.uuidString
                }.first

            guard let selected else { return nil }
            let groupIDs = Set(values.filter { $0.skill.id == selected.skill.id }.map(\.group.id))
            return DesiredMount(
                endpointID: endpointID,
                mountName: name,
                skillID: selected.skill.id,
                groupIDs: groupIDs
            )
        }.sorted {
            ($0.endpointID, $0.mountName) < ($1.endpointID, $1.mountName)
        }
    }
}
