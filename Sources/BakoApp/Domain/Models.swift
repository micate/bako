import Foundation

enum SkillEntryKind: String, Codable, CaseIterable, Hashable {
    case directoryBundle
    case flatMarkdown
}

enum AgentSupportStatus: String, Codable {
    case managed
    case sharedOnly
    case detectOnly
    case legacyImportOnly
    case experimental
    case unsupported
}

enum SkillHealth: String, Codable, CaseIterable {
    case managed
    case mounted
    case unmounted
    case externalLink
    case brokenLink
    case occupied
    case shadowed

    var title: String {
        switch self {
        case .managed: return L10n.string("health.managed")
        case .mounted: return L10n.string("health.mounted")
        case .unmounted: return L10n.string("health.unmounted")
        case .externalLink: return L10n.string("health.external_link")
        case .brokenLink: return L10n.string("health.broken_link")
        case .occupied: return L10n.string("health.occupied")
        case .shadowed: return L10n.string("health.shadowed")
        }
    }

    var isAvailableForGrouping: Bool {
        switch self {
        case .managed, .mounted, .unmounted:
            return true
        case .externalLink, .brokenLink, .occupied, .shadowed:
            return false
        }
    }
}

struct Skill: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var summary: String
    var kind: SkillEntryKind
    var fingerprint: String
    var centralPath: String
    var origins: [SkillOrigin]
    var health: SkillHealth

    var shortFingerprint: String { String(fingerprint.prefix(8)) }
}

struct SkillOrigin: Identifiable, Codable, Hashable {
    let id: UUID
    var agentID: String?
    var path: String
    var discoveredAt: Date
}

struct Endpoint: Identifiable, Codable, Hashable {
    let id: String
    var label: String
    var pathTemplate: String
    var isShared: Bool
    var consumers: [String]
    var entryKinds: Set<SkillEntryKind>
}

struct AgentDefinition: Identifiable, Codable, Hashable {
    let id: String
    var displayName: String
    var status: AgentSupportStatus
    var detectionPaths: [String]
    var nativeEndpoints: [Endpoint]
    var compatibilityEndpointIDs: [String]
    var notes: [String]
}

struct EndpointScanTarget: Hashable {
    var endpoint: Endpoint
    var originAgentID: String?
    var groupName: String
    var groupTarget: GroupTarget
}

enum GroupTarget: Codable, Hashable, Identifiable {
    case agent(String)
    case shared(String)

    var id: String {
        switch self {
        case .agent(let value): return "agent:\(value)"
        case .shared(let value): return "shared:\(value)"
        }
    }
}

struct SkillGroup: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var skillIDs: Set<UUID>
    var targets: Set<GroupTarget>
    var isEnabled: Bool
    var isSystem: Bool
    var lastEnabledAt: Date?
    var sourceID: String? = nil
}

struct DesiredMount: Hashable {
    var endpointID: String
    var mountName: String
    var skillID: UUID
    var groupIDs: Set<UUID>
}

struct ActivityRecord: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case scan, migration, mount, recovery, warning }

    let id: UUID
    var date: Date
    var kind: Kind
    var title: String
    var detail: String
    var isError: Bool
}

enum ScanSourceHealth: String, Codable, Hashable {
    case available
    case unavailable
    case empty

    var title: String {
        switch self {
        case .available: return L10n.string("source_health.available")
        case .unavailable: return L10n.string("source_health.unavailable")
        case .empty: return L10n.string("source_health.empty")
        }
    }
}

struct ScanSource: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var bookmark: Data?
    var entryKinds: Set<SkillEntryKind>
    var isEnabled: Bool
    var isInGitWorkTree: Bool
    var health: ScanSourceHealth
    var lastScannedAt: Date?
    var lastResult: String?
}

struct ScanSummary: Equatable {
    var migrated = 0
    var deduplicated = 0
    var variants = 0
    var externalLinks = 0
    var brokenLinks = 0
    var customSourceMigrated = 0
    var failures: [String] = []
}
