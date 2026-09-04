import XCTest
@testable import BakoApp

final class MountPlannerTests: XCTestCase {
    func testEnabledGroupsUnionReferencesAndPreserveSeparateAgentEndpoints() {
        let skill = makeSkill(name: "swift")
        let first = makeGroup(name: "A", skill: skill.id, targets: [.agent("codex")], enabledAt: Date(timeIntervalSince1970: 1))
        let second = makeGroup(name: "B", skill: skill.id, targets: [.agent("codex")], enabledAt: Date(timeIntervalSince1970: 2))
        let third = makeGroup(name: "C", skill: skill.id, targets: [.agent("claude")], enabledAt: Date(timeIntervalSince1970: 3))

        let mounts = MountPlanner.desiredMounts(
            groups: [first, second, third], skills: [skill],
            endpointsByAgent: ["codex": ["codex-native"], "claude": ["claude-native"]]
        )
        XCTAssertEqual(mounts.count, 2)
        XCTAssertEqual(mounts.first(where: { $0.endpointID == "codex-native" })?.groupIDs, [first.id, second.id])
    }

    func testPreferredVariantWinsForSameEndpointAndName() {
        let old = makeSkill(name: "react")
        let preferred = makeSkill(name: "react")
        let group = SkillGroup(
            id: UUID(), name: "Frontend", skillIDs: [old.id, preferred.id],
            targets: [.agent("codex")], isEnabled: true, isSystem: false, lastEnabledAt: Date()
        )
        let mounts = MountPlanner.desiredMounts(
            groups: [group], skills: [old, preferred], endpointsByAgent: ["codex": ["codex-native"]],
            preferredVariants: ["codex-native|react": preferred.id]
        )
        XCTAssertEqual(mounts.single?.skillID, preferred.id)
    }

    private func makeSkill(name: String) -> Skill {
        .init(id: UUID(), name: name, summary: "", kind: .directoryBundle,
              fingerprint: UUID().uuidString, centralPath: "/tmp/\(UUID())", origins: [], health: .managed)
    }

    private func makeGroup(name: String, skill: UUID, targets: Set<GroupTarget>, enabledAt: Date) -> SkillGroup {
        .init(id: UUID(), name: name, skillIDs: [skill], targets: targets,
              isEnabled: true, isSystem: false, lastEnabledAt: enabledAt)
    }
}

private extension Collection {
    var single: Element? { count == 1 ? first : nil }
}
