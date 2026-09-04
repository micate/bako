import AppKit
import Foundation
import SwiftUI

@MainActor
final class BakoModel: ObservableObject {
    static let shared = BakoModel()

    @Published var skills: [Skill] = []
    @Published var groups: [SkillGroup] = []
    @Published var activity: [ActivityRecord] = []
    @Published var scanSources: [ScanSource] = []
    @Published var disabledAgentIDs: Set<String> = []
    @Published var detectedAgents: [AgentDefinition] = []
    @Published var selectedSection: SidebarSection? = .skills
    @Published var isWorking = false
    @Published var showsScanConfirmation = false
    @Published var lastScanSummary: ScanSummary?
    @Published var errorMessage: String?

    let rootURL: URL
    private let store: StateStore
    private let migrationEngine: MigrationEngine
    private let recoveryEngine: RecoveryEngine
    private let skillRestoreEngine: SkillRestoreEngine
    private let skillDeletionEngine: SkillDeletionEngine
    private let linkReconciler: LinkReconciler
    private let resolver: PathResolver
    private let scanSourceManager: ScanSourceManager

    private init() {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        rootURL = applicationSupport.appendingPathComponent("Bako", isDirectory: true)
        store = StateStore(root: rootURL)
        migrationEngine = MigrationEngine(root: rootURL)
        recoveryEngine = RecoveryEngine(root: rootURL)
        skillRestoreEngine = SkillRestoreEngine()
        skillDeletionEngine = SkillDeletionEngine(root: rootURL)
        linkReconciler = LinkReconciler(root: rootURL)
        resolver = PathResolver()
        scanSourceManager = ScanSourceManager()
        Task { await load() }
    }

    func load() async {
        detectedAgents = AgentCatalog.detected(using: .default, resolver: resolver)
        let recovery = await recoveryEngine.recover()
        do {
            var state = try await store.load()
            if recovery.completed + recovery.rolledBack > 0 || !recovery.failures.isEmpty {
                state.activity.insert(.init(
                    id: UUID(), date: Date(), kind: .recovery,
                    title: L10n.string("activity.recovery.title"),
                    detail: L10n.string(
                        "activity.recovery.detail",
                        Int64(recovery.completed), Int64(recovery.rolledBack), Int64(recovery.failures.count)
                    ),
                    isError: !recovery.failures.isEmpty
                ), at: 0)
            }
            let repaired = repairMetadata(in: &state.skills)
            let repairedGroupSources = repairGroupSources(in: &state.groups)
            skills = state.skills
            groups = state.groups
            activity = state.activity
            scanSources = state.scanSources
            disabledAgentIDs = state.disabledAgentIDs
            if repaired || repairedGroupSources || recovery.completed + recovery.rolledBack > 0 || !recovery.failures.isEmpty {
                try await store.save(state)
            }
            if let first = recovery.failures.first { errorMessage = first }
        } catch {
            errorMessage = error.localizedDescription
        }
        MenuBarController.shared.refresh()
    }

    func requestScanConfirmation() {
        selectedSection = .skills
        showsScanConfirmation = true
    }

    func showScanSetup() {
        selectedSection = .skills
        showsScanConfirmation = false
    }

    func refreshDetectedAgents() {
        detectedAgents = AgentCatalog.detected(using: .default, resolver: resolver)
    }

    func scanAndImport() {
        guard !isWorking else { return }
        showsScanConfirmation = false
        isWorking = true
        Task {
            var summary = ScanSummary()
            var updatedSkills = skills
            var updatedGroups = groups

            for target in AgentCatalog.managedScanTargets(
                for: detectedAgents, excludingAgentIDs: disabledAgentIDs
            ) {
                let endpoint = target.endpoint
                guard let sourceURL = try? resolver.resolve(endpoint.pathTemplate),
                      FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
                let results = SkillScanner().scan(source: sourceURL, kinds: endpoint.entryKinds)
                var importedIDs = Set<UUID>()
                for result in results {
                    do {
                        let candidate = try result.get()
                        switch candidate.health {
                        case .externalLink: summary.externalLinks += 1
                        case .brokenLink: summary.brokenLinks += 1
                        default:
                            let outcome = try await migrationEngine.migrate(candidate, existing: updatedSkills)
                            if outcome.deduplicated { summary.deduplicated += 1 } else { summary.migrated += 1 }
                            if let existingIndex = updatedSkills.firstIndex(where: { $0.id == outcome.skillID }) {
                                if !updatedSkills[existingIndex].origins.contains(where: { $0.path == candidate.url.path }) {
                                    updatedSkills[existingIndex].origins.append(.init(
                                        id: UUID(), agentID: target.originAgentID,
                                        path: candidate.url.path, discoveredAt: Date()
                                    ))
                                }
                                importedIDs.insert(updatedSkills[existingIndex].id)
                            } else {
                                let sameNameExists = updatedSkills.contains { $0.name == candidate.name }
                                if sameNameExists { summary.variants += 1 }
                                let skill = Skill(
                                    id: outcome.skillID, name: candidate.name, summary: candidate.summary,
                                    kind: candidate.kind, fingerprint: candidate.fingerprint ?? "",
                                    centralPath: outcome.centralURL.path,
                                    origins: [.init(
                                        id: UUID(), agentID: target.originAgentID,
                                        path: candidate.url.path, discoveredAt: Date()
                                    )],
                                    health: .mounted
                                )
                                updatedSkills.append(skill)
                                importedIDs.insert(skill.id)
                            }
                        }
                    } catch {
                        summary.failures.append(error.localizedDescription)
                    }
                }
                if !importedIDs.isEmpty {
                    if let index = updatedGroups.firstIndex(where: {
                        $0.isSystem && (
                            $0.sourceID == target.endpoint.id ||
                            ($0.sourceID == nil && $0.name == target.groupName)
                        )
                    }) {
                        updatedGroups[index].sourceID = target.endpoint.id
                        updatedGroups[index].skillIDs.formUnion(importedIDs)
                        updatedGroups[index].targets.insert(target.groupTarget)
                    } else {
                        updatedGroups.append(.init(
                            id: UUID(), name: target.groupName, skillIDs: importedIDs,
                            targets: [target.groupTarget], isEnabled: true, isSystem: true,
                            lastEnabledAt: Date(), sourceID: target.endpoint.id
                        ))
                    }
                }
            }

            for sourceIndex in updatedScanSourceIndices() {
                var source = scanSources[sourceIndex]
                guard let sourceURL = scanSourceManager.resolve(source) else {
                    scanSources[sourceIndex].health = .unavailable
                    scanSources[sourceIndex].lastScannedAt = Date()
                    scanSources[sourceIndex].lastResult = L10n.string("source_health.unavailable")
                    continue
                }
                let didAccess = sourceURL.startAccessingSecurityScopedResource()
                defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }
                let results = SkillScanner().scan(source: sourceURL, kinds: source.entryKinds)
                var migratedFromSource = 0
                for result in results {
                    do {
                        let candidate = try result.get()
                        switch candidate.health {
                        case .externalLink: summary.externalLinks += 1
                        case .brokenLink: summary.brokenLinks += 1
                        default:
                            let outcome = try await migrationEngine.migrate(candidate, existing: updatedSkills)
                            if outcome.deduplicated { summary.deduplicated += 1 } else { summary.migrated += 1 }
                            summary.customSourceMigrated += 1
                            migratedFromSource += 1
                            if let existingIndex = updatedSkills.firstIndex(where: { $0.id == outcome.skillID }) {
                                if !updatedSkills[existingIndex].origins.contains(where: { $0.path == candidate.url.path }) {
                                    updatedSkills[existingIndex].origins.append(.init(
                                        id: UUID(), agentID: nil, path: candidate.url.path, discoveredAt: Date()
                                    ))
                                }
                            } else {
                                if updatedSkills.contains(where: { $0.name == candidate.name }) { summary.variants += 1 }
                                updatedSkills.append(.init(
                                    id: outcome.skillID, name: candidate.name, summary: candidate.summary,
                                    kind: candidate.kind, fingerprint: candidate.fingerprint ?? "",
                                    centralPath: outcome.centralURL.path,
                                    origins: [.init(id: UUID(), agentID: nil, path: candidate.url.path, discoveredAt: Date())],
                                    health: .managed
                                ))
                            }
                        }
                    } catch {
                        summary.failures.append("\(source.name)：\(error.localizedDescription)")
                    }
                }
                source.lastScannedAt = Date()
                source.health = results.isEmpty ? .empty : .available
                source.lastResult = results.isEmpty
                    ? L10n.string("source_health.empty")
                    : L10n.string("settings.source.migrated", Int64(migratedFromSource))
                scanSources[sourceIndex] = source
            }

            skills = updatedSkills
            groups = updatedGroups
            lastScanSummary = summary
            activity.insert(.init(
                id: UUID(), date: Date(), kind: .scan,
                title: L10n.string("activity.scan.title"),
                detail: L10n.string(
                    "activity.scan.detail", Int64(summary.migrated), Int64(summary.customSourceMigrated),
                    Int64(summary.deduplicated), Int64(summary.failures.count)
                ),
                isError: !summary.failures.isEmpty
            ), at: 0)
            isWorking = false
            await persist()
            MenuBarController.shared.refresh()
        }
    }

    func toggleGroup(_ groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].isEnabled.toggle()
        if groups[index].isEnabled { groups[index].lastEnabledAt = Date() }
        let actionTitle = L10n.string(
            groups[index].isEnabled ? "activity.group.enabled" : "activity.group.disabled",
            groups[index].name
        )
        Task {
            let endpointMap = resolvedEndpointMap()
            let endpointsByAgent = Dictionary(uniqueKeysWithValues: managedAgents.map { agent in
                (agent.id, agent.nativeEndpoints.map(\.id))
            })
            let desired = MountPlanner.desiredMounts(
                groups: groups, skills: skills, endpointsByAgent: endpointsByAgent
            )
            let result = await linkReconciler.reconcile(desired: desired, skills: skills, endpoints: endpointMap)
            activity.insert(.init(
                id: UUID(), date: Date(), kind: .mount, title: actionTitle,
                detail: L10n.string(
                    "activity.links.changed", Int64(result.created), Int64(result.removed), Int64(result.failures.count)
                ),
                isError: !result.failures.isEmpty
            ), at: 0)
            if let first = result.failures.first { errorMessage = first }
            await persist()
        }
        MenuBarController.shared.refresh()
    }

    func createGroup() {
        let number = groups.filter { !$0.isSystem }.count + 1
        groups.append(.init(
            id: UUID(), name: L10n.string("groups.default_name", Int64(number)), skillIDs: [], targets: [],
            isEnabled: false, isSystem: false, lastEnabledAt: nil
        ))
        selectedSection = .groups
        Task { await persist() }
    }

    func deleteGroup(_ groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        groups.removeAll { $0.id == groupID }

        Task {
            let endpointMap = resolvedEndpointMap()
            let endpointsByAgent = Dictionary(uniqueKeysWithValues: managedAgents.map { agent in
                (agent.id, agent.nativeEndpoints.map(\.id))
            })
            let desired = MountPlanner.desiredMounts(
                groups: groups, skills: skills, endpointsByAgent: endpointsByAgent
            )
            let result = await linkReconciler.reconcile(
                desired: desired, skills: skills, endpoints: endpointMap
            )
            activity.insert(.init(
                id: UUID(), date: Date(), kind: .mount,
                title: L10n.string("activity.group.deleted", group.name),
                detail: L10n.string("activity.links.removed", Int64(result.removed), Int64(result.failures.count)),
                isError: !result.failures.isEmpty
            ), at: 0)
            if let first = result.failures.first { errorMessage = first }
            await persist()
        }
        MenuBarController.shared.refresh()
    }

    func chooseScanSource() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("settings.source.panel_title")
        panel.message = L10n.string("settings.source.panel_message")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let endpointURLs = detectedAgents.flatMap(\.nativeEndpoints).compactMap { try? resolver.resolve($0.pathTemplate) }
            let existingURLs = scanSources.compactMap { scanSourceManager.resolve($0) } + endpointURLs + [rootURL]
            let source = try scanSourceManager.makeSource(
                url: url, resolver: resolver, centralStore: rootURL, existing: existingURLs
            )
            if source.isInGitWorkTree {
                let alert = NSAlert()
                alert.messageText = L10n.string("settings.source.git_title")
                alert.informativeText = L10n.string("settings.source.git_detail")
                alert.addButton(withTitle: L10n.string("settings.source.git_add"))
                alert.addButton(withTitle: L10n.string("common.cancel"))
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
            scanSources.append(source)
            Task { await persist() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleScanSource(_ id: UUID) {
        guard let index = scanSources.firstIndex(where: { $0.id == id }) else { return }
        scanSources[index].isEnabled.toggle()
        Task { await persist() }
    }

    func setFlatMarkdown(_ enabled: Bool, for id: UUID) {
        guard let index = scanSources.firstIndex(where: { $0.id == id }) else { return }
        if enabled { scanSources[index].entryKinds.insert(.flatMarkdown) }
        else { scanSources[index].entryKinds.remove(.flatMarkdown) }
        Task { await persist() }
    }

    func removeScanSource(_ id: UUID) {
        scanSources.removeAll { $0.id == id }
        Task { await persist() }
    }

    var managedAgents: [AgentDefinition] {
        detectedAgents.filter { $0.status == .managed && !disabledAgentIDs.contains($0.id) }
    }

    func isAgentManagementEnabled(_ agentID: String) -> Bool {
        !disabledAgentIDs.contains(agentID)
    }

    func toggleAgentManagement(_ agentID: String) {
        guard let agent = detectedAgents.first(where: { $0.id == agentID }),
              agent.status == .managed else { return }
        if disabledAgentIDs.contains(agentID) {
            disabledAgentIDs.remove(agentID)
        } else {
            disabledAgentIDs.insert(agentID)
        }
        let enabled = isAgentManagementEnabled(agentID)
        Task {
            let endpointMap = resolvedEndpointMap()
            let endpointsByAgent = Dictionary(uniqueKeysWithValues: managedAgents.map { managedAgent in
                (managedAgent.id, managedAgent.nativeEndpoints.map(\.id))
            })
            let desired = MountPlanner.desiredMounts(
                groups: groups, skills: skills, endpointsByAgent: endpointsByAgent
            )
            let result = await linkReconciler.reconcile(
                desired: desired, skills: skills, endpoints: endpointMap
            )
            activity.insert(.init(
                id: UUID(), date: Date(), kind: .mount,
                title: L10n.string(
                    enabled ? "activity.agent.started" : "activity.agent.stopped", agent.displayName
                ),
                detail: L10n.string(
                    "activity.links.changed", Int64(result.created), Int64(result.removed), Int64(result.failures.count)
                ),
                isError: !result.failures.isEmpty
            ), at: 0)
            if let first = result.failures.first { errorMessage = first }
            await persist()
        }
    }

    func clearActivity() {
        activity.removeAll()
        Task { await persist() }
    }

    func saveGroup(_ group: SkillGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        let previous = groups[index]
        var updated = group
        if updated.isEnabled && !previous.isEnabled { updated.lastEnabledAt = Date() }
        groups[index] = updated

        let needsReconcile = (previous.isEnabled || updated.isEnabled) && (
            previous.isEnabled != updated.isEnabled ||
            previous.skillIDs != updated.skillIDs ||
            previous.targets != updated.targets
        )

        Task {
            if needsReconcile {
                let endpointMap = resolvedEndpointMap()
                let endpointsByAgent = Dictionary(uniqueKeysWithValues: managedAgents.map { agent in
                    (agent.id, agent.nativeEndpoints.map(\.id))
                })
                let desired = MountPlanner.desiredMounts(
                    groups: groups, skills: skills, endpointsByAgent: endpointsByAgent
                )
                let result = await linkReconciler.reconcile(
                    desired: desired, skills: skills, endpoints: endpointMap
                )
                activity.insert(.init(
                    id: UUID(), date: Date(), kind: .mount,
                    title: L10n.string("activity.group.applied", updated.name),
                    detail: L10n.string(
                        "activity.links.changed", Int64(result.created), Int64(result.removed), Int64(result.failures.count)
                    ),
                    isError: !result.failures.isEmpty
                ), at: 0)
                if let first = result.failures.first { errorMessage = first }
            }
            await persist()
        }
        MenuBarController.shared.refresh()
    }

    func moveGroups(fromOffsets source: IndexSet, toOffset destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        Task { await persist() }
    }

    func revealCentralStore() {
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([rootURL])
    }

    func restoreSkillsToSharedDirectory() {
        guard !isWorking, !skills.isEmpty,
              let destination = try? resolver.resolve(AgentCatalog.sharedAgentsEndpoint.pathTemplate) else { return }
        isWorking = true
        Task {
            let result = await skillRestoreEngine.restore(
                skills,
                to: destination,
                linkRoots: Array(resolvedEndpointMap().values)
            )
            let restoredIDs = result.restoredSkillIDs
            if !restoredIDs.isEmpty {
                skills.removeAll { restoredIDs.contains($0.id) }
                for index in groups.indices {
                    groups[index].skillIDs.subtract(restoredIDs)
                }
            }
            activity.insert(.init(
                id: UUID(), date: Date(), kind: .recovery,
                title: L10n.string("activity.skills_restored.title"),
                detail: L10n.string(
                    "activity.skills_restored.detail", Int64(restoredIDs.count),
                    Int64(result.relinked), Int64(result.failures.count)
                ),
                isError: !result.failures.isEmpty
            ), at: 0)
            if let first = result.failures.first { errorMessage = first }
            isWorking = false
            await persist()
            MenuBarController.shared.refresh()
        }
    }

    func deleteSkill(_ skillID: UUID) {
        guard !isWorking, let skill = skills.first(where: { $0.id == skillID }) else { return }
        isWorking = true
        Task {
            let result = await skillDeletionEngine.delete(
                skill,
                linkRoots: Array(resolvedEndpointMap().values)
            )
            if result.deleted {
                skills.removeAll { $0.id == skillID }
                for index in groups.indices {
                    groups[index].skillIDs.remove(skillID)
                }
            }
            activity.insert(.init(
                id: UUID(), date: Date(), kind: .migration,
                title: L10n.string("activity.skill_deleted.title", skill.name),
                detail: L10n.string(
                    "activity.skill_deleted.detail", Int64(result.removedLinks), Int64(result.failures.count)
                ),
                isError: !result.failures.isEmpty
            ), at: 0)
            if let first = result.failures.first { errorMessage = first }
            isWorking = false
            await persist()
            MenuBarController.shared.refresh()
        }
    }

    private func persist() async {
        do {
            try await store.save(.init(
                skills: skills, groups: groups, activity: Array(activity.prefix(200)),
                scanSources: scanSources, disabledAgentIDs: disabledAgentIDs
            ))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolvedEndpointMap() -> [String: URL] {
        var endpoints = [String: URL]()
        for endpoint in detectedAgents.flatMap(\.nativeEndpoints) + [AgentCatalog.sharedAgentsEndpoint] {
            if let url = try? resolver.resolve(endpoint.pathTemplate) { endpoints[endpoint.id] = url }
        }
        return endpoints
    }

    private func updatedScanSourceIndices() -> [Int] {
        scanSources.indices.filter { scanSources[$0].isEnabled }
    }

    private func repairMetadata(in skills: inout [Skill]) -> Bool {
        var changed = false
        for index in skills.indices {
            let centralURL = URL(fileURLWithPath: skills[index].centralPath)
            let metadataURL = skills[index].kind == .directoryBundle
                ? centralURL.appendingPathComponent("SKILL.md")
                : centralURL
            guard let text = try? String(contentsOf: metadataURL, encoding: .utf8) else { continue }
            let metadata = SkillMetadataParser.parse(text)
            if let name = metadata.name, skills[index].name != name {
                skills[index].name = name
                changed = true
            }
            if let description = metadata.description, skills[index].summary != description {
                skills[index].summary = description
                changed = true
            }
        }
        return changed
    }

    private func repairGroupSources(in groups: inout [SkillGroup]) -> Bool {
        let sourceByTarget = Dictionary(uniqueKeysWithValues:
            AgentCatalog.managedScanTargets(for: AgentCatalog.bundled).map {
                ($0.groupTarget, $0.endpoint.id)
            }
        )
        var changed = false
        for index in groups.indices where groups[index].isSystem && groups[index].sourceID == nil {
            guard let target = groups[index].targets.first,
                  groups[index].targets.count == 1,
                  let sourceID = sourceByTarget[target] else { continue }
            groups[index].sourceID = sourceID
            changed = true
        }
        return changed
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case skills
    case groups
    case activity
    case settings

    var id: String { rawValue }
    var title: String {
        switch self {
        case .skills: return L10n.string("sidebar.skills")
        case .groups: return L10n.string("sidebar.groups")
        case .activity: return L10n.string("sidebar.activity")
        case .settings: return L10n.string("sidebar.settings")
        }
    }
    var systemImage: String {
        switch self {
        case .skills: return "shippingbox"
        case .groups: return "square.stack.3d.up"
        case .activity: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}
