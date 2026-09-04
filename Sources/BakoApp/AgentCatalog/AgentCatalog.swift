import Foundation

struct AgentCatalog {
    static let sharedAgentsEndpoint = Endpoint(
        id: "shared-agents", label: L10n.string("agent.shared"), pathTemplate: "~/.agents/skills",
        isShared: true, consumers: ["codex", "deepseek-harness", "openclaw", "kilo", "zoo"],
        entryKinds: [.directoryBundle]
    )

    static let bundled: [AgentDefinition] = [
        .init(id: "codex", displayName: "OpenAI Codex", status: .managed,
              detectionPaths: ["~/.codex"],
              nativeEndpoints: [.init(id: "codex-native", label: "Codex", pathTemplate: "~/.codex/skills", isShared: false, consumers: ["codex"], entryKinds: [.directoryBundle])],
              compatibilityEndpointIDs: ["shared-agents"], notes: []),
        .init(id: "claude", displayName: "Claude Code", status: .managed,
              detectionPaths: ["~/.claude"],
              nativeEndpoints: [.init(id: "claude-native", label: "Claude Code", pathTemplate: "~/.claude/skills", isShared: false, consumers: ["claude"], entryKinds: [.directoryBundle])],
              compatibilityEndpointIDs: [], notes: []),
        .init(id: "cursor", displayName: "Cursor", status: .experimental,
              detectionPaths: ["~/.cursor"], nativeEndpoints: [], compatibilityEndpointIDs: ["shared-agents"],
              notes: [L10n.string("agent.note.user_mount_unverified")]),
        .init(id: "qoder", displayName: "Qoder", status: .managed,
              detectionPaths: ["~/.qoder"],
              nativeEndpoints: [.init(id: "qoder-native", label: "Qoder", pathTemplate: "~/.qoder/skills", isShared: false, consumers: ["qoder"], entryKinds: [.directoryBundle])],
              compatibilityEndpointIDs: [], notes: []),
        .init(id: "qoder-cn", displayName: "Qoder CN IDE", status: .managed,
              detectionPaths: ["~/.lingma"],
              nativeEndpoints: [.init(id: "qoder-cn-native", label: "Qoder CN IDE", pathTemplate: "~/.lingma/skills", isShared: false, consumers: ["qoder-cn"], entryKinds: [.directoryBundle])],
              compatibilityEndpointIDs: [], notes: []),
        .init(id: "deepseek-harness", displayName: "DeepSeek Harness", status: .managed,
              detectionPaths: ["${DSH_HOME:-~/.dsh}"],
              nativeEndpoints: [.init(id: "deepseek-native", label: "DeepSeek Harness", pathTemplate: "${DSH_HOME:-~/.dsh}/skills", isShared: false, consumers: ["deepseek-harness"], entryKinds: [.directoryBundle, .flatMarkdown])],
              compatibilityEndpointIDs: ["shared-agents"], notes: []),
        .init(id: "zcode", displayName: "ZCode", status: .managed,
              detectionPaths: ["~/.zcode"],
              nativeEndpoints: [.init(id: "zcode-native", label: "ZCode", pathTemplate: "~/.zcode/skills", isShared: false, consumers: ["zcode"], entryKinds: [.directoryBundle])],
              compatibilityEndpointIDs: [], notes: []),
        .init(id: "openclaw", displayName: "OpenClaw", status: .managed,
              detectionPaths: ["~/.openclaw"],
              nativeEndpoints: [.init(id: "openclaw-native", label: "OpenClaw", pathTemplate: "~/.openclaw/skills", isShared: false, consumers: ["openclaw"], entryKinds: [.directoryBundle])],
              compatibilityEndpointIDs: ["shared-agents"], notes: []),
        .init(id: "kilo", displayName: "Kilo Code", status: .managed,
              detectionPaths: ["~/.kilo"],
              nativeEndpoints: [.init(id: "kilo-native", label: "Kilo Code", pathTemplate: "~/.kilo/skills", isShared: false, consumers: ["kilo"], entryKinds: [.directoryBundle])],
              compatibilityEndpointIDs: ["shared-agents"], notes: []),
        .init(id: "zoo", displayName: L10n.string("agent.zoo_legacy_name"), status: .managed,
              detectionPaths: ["~/.roo"],
              nativeEndpoints: [.init(id: "zoo-native", label: "Zoo Code", pathTemplate: "~/.roo/skills", isShared: false, consumers: ["zoo"], entryKinds: [.directoryBundle])],
              compatibilityEndpointIDs: ["shared-agents"], notes: [L10n.string("agent.note.no_mode_specific")]),
        .init(id: "devin", displayName: "Devin Desktop", status: .detectOnly,
              detectionPaths: ["~/Library/Application Support/Devin"], nativeEndpoints: [], compatibilityEndpointIDs: [],
              notes: [L10n.string("agent.note.project_only")])
    ]

    static func managedScanTargets(
        for agents: [AgentDefinition], excludingAgentIDs: Set<String> = []
    ) -> [EndpointScanTarget] {
        let nativeTargets = agents
            .filter { $0.status == .managed && !excludingAgentIDs.contains($0.id) }
            .flatMap { agent in
                agent.nativeEndpoints.map { endpoint in
                    EndpointScanTarget(
                        endpoint: endpoint,
                        originAgentID: agent.id,
                        groupName: L10n.string("agent.imported_group", agent.displayName),
                        groupTarget: .agent(agent.id)
                    )
                }
            }
        return nativeTargets + [
            EndpointScanTarget(
                endpoint: sharedAgentsEndpoint,
                originAgentID: nil,
                groupName: L10n.string("agent.imported_group", L10n.string("agent.shared")),
                groupTarget: .shared(sharedAgentsEndpoint.id)
            )
        ]
    }

    static func detected(using fileManager: FileManager = .default, resolver: PathResolver = .init()) -> [AgentDefinition] {
        bundled.filter { agent in
            agent.detectionPaths.contains { template in
                guard let url = try? resolver.resolve(template) else { return false }
                return fileManager.fileExists(atPath: url.path)
            }
        }
    }
}
