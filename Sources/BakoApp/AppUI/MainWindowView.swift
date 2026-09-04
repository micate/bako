import AppKit
import SwiftUI

private enum AppStyle {
    static let sidebarWidth: CGFloat = 128
    static let titlebarInset: CGFloat = 42
    static let contentInset: CGFloat = 8
    static let contentRadius: CGFloat = 10
    static let pagePadding: CGFloat = 20
    static let pageSpacing: CGFloat = 14
    static let panelRadius: CGFloat = 7
    static let rowVerticalPadding: CGFloat = 4
}

struct MainWindowView: View {
    @EnvironmentObject private var model: BakoModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Color.clear.frame(height: AppStyle.titlebarInset)
                ForEach(SidebarSection.allCases) { section in
                    SidebarButton(
                        section: section,
                        isSelected: model.selectedSection == section
                    ) {
                        model.selectedSection = section
                    }
                }
                Spacer()
                SidebarFooter()
            }
            .frame(width: AppStyle.sidebarWidth)
            .background(Color.clear)

            content
                .frame(minWidth: 660, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: AppStyle.contentRadius, style: .continuous))
                .padding(AppStyle.contentInset)
        }
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Color.black.opacity(colorScheme == .dark ? 0.18 : 0.035)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .alert(L10n.string("scan.confirmation.title"), isPresented: $model.showsScanConfirmation) {
            Button(L10n.string("common.cancel"), role: .cancel) { }
            Button(L10n.string("scan.confirmation.action")) { model.scanAndImport() }
        } message: {
            Text(scanConfirmationDetail)
        }
        .alert(L10n.string("scan.failure.title"), isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button(L10n.string("common.ok")) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? L10n.string("common.unknown_error"))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.selectedSection ?? .skills {
        case .skills: SkillsView()
        case .groups: GroupsView()
        case .activity: ActivityView()
        case .settings: SettingsView()
        }
    }

    private var scanConfirmationDetail: String {
        let agentNames = model.managedAgents.map(\.displayName)
        let scope = agentNames.isEmpty
            ? L10n.string("scan.scope.none")
            : L10n.string("scan.scope.selected", agentNames.joined(separator: ", "))
        return L10n.string("scan.confirmation.detail", scope)
    }
}

private struct SidebarFooter: View {
    @EnvironmentObject private var updateController: UpdateController

    private var currentVersionLabel: String {
        guard let version = updateController.currentVersion else {
            return L10n.string("version.development")
        }
        return L10n.string("version.current", version)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text("Bako")
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(currentVersionLabel)
                    .foregroundColor(.secondary)
            }
            .font(.system(size: 11))
            .lineLimit(1)

            switch updateController.status {
            case .checking:
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text(L10n.string("version.checking"))
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            case let .available(version):
                Button(action: updateController.checkForUpdates) {
                    Label(L10n.string("version.update_available", version), systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help(L10n.string("version.update_help"))
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.bottom, 12)
    }
}

private struct SidebarButton: View {
    var section: SidebarSection
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 15)
                Text(section.title)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
            .foregroundColor(isSelected ? .primary : .secondary)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PageHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SkillsView: View {
    @EnvironmentObject private var model: BakoModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.pageSpacing) {
            PageHeader(title: L10n.string("sidebar.skills"), subtitle: L10n.string("scan.subtitle"))
            AgentManagementPanel()
            if model.isWorking {
                ProgressView(L10n.string("scan.progress"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.skills.isEmpty {
                EmptyState(
                    icon: "shippingbox",
                    title: L10n.string("scan.empty.title"),
                    detail: L10n.string("scan.empty.detail")
                )
            } else {
                SkillCatalogList(
                    skills: model.skills,
                    onDelete: model.deleteSkill,
                    deletionDisabled: model.isWorking
                )
            }
        }
        .padding(AppStyle.pagePadding)
    }
}

private struct AgentManagementPanel: View {
    @EnvironmentObject private var model: BakoModel

    private let agentRowHeight: CGFloat = 28

    private var agentListHeight: CGFloat {
        let visibleRowCount = min(max(CGFloat(model.detectedAgents.count), 1), 4.5)
        return visibleRowCount * agentRowHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(L10n.string("scan.range"), systemImage: "cpu")
                    .font(.system(size: 12, weight: .semibold))
                Text(L10n.string("scan.range.hint"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
                Button(action: model.refreshDetectedAgents) {
                    Label(L10n.string("scan.refresh_agents"), systemImage: "desktopcomputer")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isWorking)
                .fixedSize()
                Button(action: model.requestScanConfirmation) {
                    Label(L10n.string("scan.action"), systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .controlSize(.small)
                .disabled(model.isWorking)
                .help(L10n.string("scan.action.help"))
                .fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(height: 36)

            Divider()

            if model.detectedAgents.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .foregroundColor(.secondary)
                    Text(L10n.string("scan.no_agents"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: agentListHeight)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.detectedAgents) { agent in
                            agentRow(agent)
                        }
                    }
                }
                .frame(height: agentListHeight)
            }
        }
        .linearPanel()
    }

    @ViewBuilder
    private func agentRow(_ agent: AgentDefinition) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if agent.status == .managed {
                Toggle(isOn: Binding(
                    get: { model.isAgentManagementEnabled(agent.id) },
                    set: { enabled in
                        if model.isAgentManagementEnabled(agent.id) != enabled {
                            model.toggleAgentManagement(agent.id)
                        }
                    }
                )) {
                    agentDescription(agent)
                }
                .toggleStyle(.checkbox)
                .disabled(model.isWorking)
                .help(L10n.string("scan.agent_toggle.help"))
            } else {
                agentDescription(agent)
                Spacer(minLength: 8)
                Text(statusTitle(agent.status))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: agentRowHeight)
        .overlay(alignment: .bottom) {
            if agent.id != model.detectedAgents.last?.id { Divider() }
        }
    }

    private func agentDescription(_ agent: AgentDefinition) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(agent.displayName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .layoutPriority(1)
            if !agent.nativeEndpoints.isEmpty {
                Text(agent.nativeEndpoints.map(\.pathTemplate).joined(separator: " · "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if !agent.notes.isEmpty {
                Text(agent.notes.joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusTitle(_ status: AgentSupportStatus) -> String {
        switch status {
        case .managed: return ""
        case .detectOnly: return L10n.string("agent.status.detect_only")
        case .experimental: return L10n.string("agent.status.experimental")
        default: return status.rawValue
        }
    }
}

private struct SkillCatalogList: View {
    var skills: [Skill]
    var selection: Binding<Set<UUID>>? = nil
    var fixedHeight: CGFloat? = nil
    var showsStatus = true
    var onDelete: ((UUID) -> Void)? = nil
    var deletionDisabled = false
    @State private var searchText = ""
    @State private var skillPendingDeletion: Skill?

    private var filteredSkills: [Skill] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return skills }
        return skills.filter { skill in
            var fields = [skill.name, skill.summary] + skill.origins.map(\.path)
            if showsStatus { fields.append(skill.health.title) }
            let searchable = fields
                .joined(separator: " ")
            return searchable.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(L10n.string("scan.search.placeholder"), text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.string("scan.search.clear"))
                }
                if selection != nil {
                    Divider().frame(height: 18)
                    Button(searchText.isEmpty ? L10n.string("scan.select_all") : L10n.string("scan.select_all_results"), action: selectAllVisible)
                        .buttonStyle(.borderless)
                    Button(searchText.isEmpty ? L10n.string("scan.invert_selection") : L10n.string("scan.invert_results"), action: invertVisibleSelection)
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)

            Divider()

            if filteredSkills.isEmpty {
                Text(L10n.string("scan.no_matches"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredSkills) { skill in
                            row(for: skill)
                            if skill.id != filteredSkills.last?.id { Divider() }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: fixedHeight)
        .linearPanel()
        .alert(item: $skillPendingDeletion) { skill in
            Alert(
                title: Text(L10n.string("scan.delete.confirmation", skill.name)),
                message: Text(L10n.string("scan.delete.detail")),
                primaryButton: .destructive(Text(L10n.string("common.delete"))) {
                    onDelete?(skill.id)
                },
                secondaryButton: .cancel(Text(L10n.string("common.cancel")))
            )
        }
    }

    @ViewBuilder
    private func row(for skill: Skill) -> some View {
        if let selection {
            HStack(alignment: .center, spacing: 10) {
                Toggle("", isOn: selectionBinding(for: skill.id, selection: selection))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .fixedSize()
                SkillCatalogRow(skill: skill, showsStatus: showsStatus)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        } else {
            SkillCatalogRow(
                skill: skill,
                showsStatus: showsStatus,
                onDelete: onDelete == nil ? nil : { skillPendingDeletion = skill },
                deletionDisabled: deletionDisabled
            )
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
    }

    private func selectionBinding(for id: UUID, selection: Binding<Set<UUID>>) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue.contains(id) },
            set: { isSelected in
                var updated = selection.wrappedValue
                if isSelected { updated.insert(id) } else { updated.remove(id) }
                selection.wrappedValue = updated
            }
        )
    }

    private func selectAllVisible() {
        guard let selection else { return }
        var updated = selection.wrappedValue
        updated.formUnion(filteredSkills.map(\.id))
        selection.wrappedValue = updated
    }

    private func invertVisibleSelection() {
        guard let selection else { return }
        var updated = selection.wrappedValue
        for id in filteredSkills.map(\.id) {
            if updated.contains(id) { updated.remove(id) } else { updated.insert(id) }
        }
        selection.wrappedValue = updated
    }
}

private struct SkillCatalogRow: View {
    var skill: Skill
    var showsStatus = true
    var onDelete: (() -> Void)? = nil
    var deletionDisabled = false

    var body: some View {
        HStack(spacing: 10) {
            if showsStatus {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .font(.system(size: 12))
                    .frame(width: 18)
                    .help(L10n.string("scan.status.help", skill.health.title))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name).font(.system(size: 13, weight: .medium))
                Text(skill.summary.isEmpty ? skill.origins.first?.path ?? "" : skill.summary)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(deletionDisabled)
                .help(L10n.string("scan.delete.action"))
                .accessibilityLabel(L10n.string("scan.delete.skill", skill.name))
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(L10n.string("common.reveal_in_finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: skill.centralPath)])
            }
            if let onDelete {
                Divider()
                Button(L10n.string("scan.delete.action"), role: .destructive, action: onDelete)
                    .disabled(deletionDisabled)
            }
        }
    }

    private var statusIcon: String {
        switch skill.health {
        case .managed, .mounted: return "checkmark.circle.fill"
        case .brokenLink, .occupied: return "exclamationmark.triangle.fill"
        case .externalLink: return "link"
        default: return "circle"
        }
    }

    private var statusColor: Color {
        [.brokenLink, .occupied].contains(skill.health) ? .orange : .accentColor
    }
}

private struct GroupsView: View {
    @EnvironmentObject private var model: BakoModel
    @State private var selectedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.pageSpacing) {
            HStack(alignment: .center, spacing: 12) {
                PageHeader(title: L10n.string("sidebar.groups"), subtitle: L10n.string("groups.subtitle"))
                Button(action: model.createGroup) {
                    Label(L10n.string("groups.new"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            if model.groups.isEmpty {
                EmptyState(
                    icon: "square.stack.3d.up",
                    title: L10n.string("groups.empty.title"),
                    detail: L10n.string("groups.empty.detail"),
                    buttonTitle: L10n.string("groups.new"),
                    action: model.createGroup
                )
            } else {
                HStack(spacing: 0) {
                    List(selection: $selectedID) {
                        ForEach(model.groups) { group in
                            GroupRow(group: group)
                                .tag(group.id)
                        }
                        .onMove(perform: model.moveGroups)
                    }
                    .listStyle(.plain)
                    .frame(width: 220)
                    .background(Color(nsColor: .controlBackgroundColor))

                    Divider()

                    if let groupID = selectedID ?? model.groups.first?.id,
                       let group = model.groups.first(where: { $0.id == groupID }) {
                        GroupDetailView(group: group)
                            .id(groupID)
                    } else {
                        EmptyState(
                            icon: "square.stack.3d.up",
                            title: L10n.string("groups.select.title"),
                            detail: L10n.string("groups.select.detail")
                        )
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: AppStyle.panelRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppStyle.panelRadius, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }
            }
        }
        .padding(AppStyle.pagePadding)
        .onAppear {
            if selectedID == nil { selectedID = model.groups.first?.id }
        }
        .onChange(of: model.groups.map(\.id)) { ids in
            if selectedID == nil || !ids.contains(selectedID!) { selectedID = ids.last }
        }
    }

    private struct GroupRow: View {
        var group: SkillGroup

        var body: some View {
            HStack(spacing: 8) {
                Circle()
                    .fill(group.isEnabled ? Color.accentColor : Color.secondary.opacity(0.28))
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(L10n.string(
                        "groups.summary",
                        Int64(group.skillIDs.count),
                        Int64(group.targets.count)
                    ))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
                    .help(L10n.string("groups.reorder.help"))
            }
            .padding(.vertical, AppStyle.rowVerticalPadding)
            .contentShape(Rectangle())
        }
    }
}

private struct GroupDetailView: View {
    @EnvironmentObject private var model: BakoModel
    let group: SkillGroup
    @State private var draft: SkillGroup
    @FocusState private var nameIsFocused: Bool
    @State private var showsDeleteConfirmation = false

    init(group: SkillGroup) {
        self.group = group
        _draft = State(initialValue: group)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("groups.name")).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                        TextField(L10n.string("groups.name.placeholder"), text: $draft.name)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, weight: .medium))
                            .focused($nameIsFocused)
                            .frame(minWidth: 240)
                    }
                    Toggle(L10n.string("common.enable"), isOn: $draft.isEnabled)
                        .toggleStyle(.switch)
                        .padding(.bottom, 4)
                        .fixedSize()
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(L10n.string("groups.apply_to"))
                    LazyVGrid(columns: targetColumns, alignment: .leading, spacing: 8) {
                        ForEach(model.managedAgents) { agent in
                            targetToggle(agent.displayName, target: .agent(agent.id))
                        }
                        targetToggle(L10n.string("agent.shared"), target: .shared("shared-agents"))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: AppStyle.panelRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppStyle.panelRadius, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.72), lineWidth: 1)
                    }
                }
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("Skills")
                    if groupableSkills.isEmpty {
                        Text(L10n.string("groups.no_healthy_skills"))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        SkillCatalogList(
                            skills: groupableSkills,
                            selection: skillSelectionBinding,
                            showsStatus: false
                        )
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: 620, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label(L10n.string("groups.delete"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
                if hasUnsavedChanges {
                    Text(L10n.string("groups.unsaved_changes"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(L10n.string("groups.save")) {
                    model.saveGroup(draft)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasUnsavedChanges || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .alert(L10n.string("groups.delete.confirmation", draft.name), isPresented: $showsDeleteConfirmation) {
            Button(L10n.string("common.cancel"), role: .cancel) { }
            Button(L10n.string("common.delete"), role: .destructive) { model.deleteGroup(draft.id) }
        } message: {
            Text(L10n.string(draft.isSystem
                 ? "groups.delete.system_detail"
                 : "groups.delete.detail"))
        }
    }

    private var targetColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)]
    }

    private func targetToggle(_ title: String, target: GroupTarget) -> some View {
        Toggle(title, isOn: targetBinding(target))
            .toggleStyle(.checkbox)
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
    }

    private var skillSelectionBinding: Binding<Set<UUID>> {
        Binding(
            get: { draft.skillIDs },
            set: { draft.skillIDs = $0 }
        )
    }

    private var hasUnsavedChanges: Bool {
        draft.name != group.name ||
        draft.skillIDs != group.skillIDs ||
        draft.targets != group.targets ||
        draft.isEnabled != group.isEnabled
    }

    private var groupableSkills: [Skill] {
        model.skills.filter { $0.health.isAvailableForGrouping }
    }

    private func targetBinding(_ target: GroupTarget) -> Binding<Bool> {
        Binding(get: { draft.targets.contains(target) }, set: { enabled in
            if enabled { draft.targets.insert(target) } else { draft.targets.remove(target) }
        })
    }
}

private struct ActivityView: View {
    @EnvironmentObject private var model: BakoModel
    @State private var showsClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.pageSpacing) {
            HStack(alignment: .center, spacing: 12) {
                PageHeader(title: L10n.string("sidebar.activity"), subtitle: L10n.string("activity.subtitle"))
                Button(role: .destructive) {
                    showsClearConfirmation = true
                } label: {
                    Label(L10n.string("common.clear"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(model.activity.isEmpty)
            }
            if model.activity.isEmpty {
                EmptyState(
                    icon: "clock.arrow.circlepath",
                    title: L10n.string("activity.empty.title"),
                    detail: L10n.string("activity.empty.detail")
                )
            } else {
                List(model.activity) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.isError ? "exclamationmark.triangle.fill" : "checkmark.circle")
                            .foregroundColor(item.isError ? .orange : .accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.system(size: 13, weight: .medium))
                            Text(item.detail)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        .layoutPriority(1)
                        Spacer()
                        Text(item.date, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize()
                    }.padding(.vertical, AppStyle.rowVerticalPadding)
                }
                .listStyle(.plain)
                .linearPanel()
            }
        }
        .padding(AppStyle.pagePadding)
        .alert(L10n.string("activity.clear.confirmation"), isPresented: $showsClearConfirmation) {
            Button(L10n.string("common.cancel"), role: .cancel) { }
            Button(L10n.string("common.clear"), role: .destructive, action: model.clearActivity)
        } message: {
            Text(L10n.string("activity.clear.detail"))
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: BakoModel
    @State private var showsRestoreConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.pageSpacing) {
            PageHeader(title: L10n.string("sidebar.settings"), subtitle: L10n.string("settings.subtitle"))
            SettingsSection(title: L10n.string("settings.central_storage"), icon: "externaldrive") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(model.rootURL.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(L10n.string("common.reveal_in_finder"), action: model.revealCentralStore)
                            .controlSize(.small)
                            .fixedSize()
                    }
                    Divider()
                    HStack(alignment: .center, spacing: 12) {
                        Text(L10n.string("settings.restore.detail"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(L10n.string("settings.restore.action"), role: .destructive) {
                            showsRestoreConfirmation = true
                        }
                        .controlSize(.small)
                        .fixedSize()
                        .disabled(model.skills.isEmpty || model.isWorking)
                    }
                }
            }
            SettingsSection(title: L10n.string("settings.custom_sources"), icon: "folder.badge.plus", contentPadding: 0) {
                VStack(spacing: 0) {
                    if model.scanSources.isEmpty {
                        HStack {
                            Text(L10n.string("settings.source.empty_detail"))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(L10n.string("settings.source.add"), action: model.chooseScanSource)
                                .controlSize(.small)
                                .fixedSize()
                        }
                        .padding(10)
                    } else {
                        ForEach(model.scanSources) { source in
                            HStack(spacing: 10) {
                                Image(systemName: source.health == .unavailable ? "exclamationmark.triangle.fill" : "folder")
                                    .foregroundColor(source.health == .unavailable ? .orange : .accentColor)
                                    .font(.system(size: 12))
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(source.name).font(.system(size: 13, weight: .medium))
                                        if source.isInGitWorkTree {
                                            Label("Git", systemImage: "arrow.triangle.branch").font(.caption).foregroundColor(.orange)
                                        }
                                    }
                                    Text(source.path).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary).lineLimit(1)
                                    Text(source.lastResult ?? source.health.title).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Toggle("Markdown", isOn: Binding(
                                    get: { source.entryKinds.contains(.flatMarkdown) },
                                    set: { model.setFlatMarkdown($0, for: source.id) }
                                ))
                                .toggleStyle(.checkbox)
                                .help(L10n.string("settings.source.markdown.help"))
                                Toggle(L10n.string("common.enable"), isOn: Binding(
                                    get: { source.isEnabled },
                                    set: { _ in model.toggleScanSource(source.id) }
                                ))
                                .toggleStyle(.switch)
                                .labelsHidden()
                                Button(role: .destructive) { model.removeScanSource(source.id) } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help(L10n.string("settings.source.remove.help"))
                            }
                            .padding(10)
                            Divider()
                        }
                        HStack {
                            Text(L10n.string("settings.source.footer"))
                                .font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Button(L10n.string("settings.source.add"), action: model.chooseScanSource)
                                .controlSize(.small)
                                .fixedSize()
                        }
                        .padding(10)
                    }
                }
            }
            Spacer()
        }
        .padding(AppStyle.pagePadding)
        .alert(L10n.string("settings.restore.confirmation"), isPresented: $showsRestoreConfirmation) {
            Button(L10n.string("common.cancel"), role: .cancel) { }
            Button(L10n.string("settings.restore.action"), role: .destructive) {
                model.restoreSkillsToSharedDirectory()
            }
        } message: {
            Text(L10n.string("settings.restore.confirmation_detail"))
        }
    }
}

private struct SettingsSection<Content: View>: View {
    var title: String
    var icon: String
    var contentPadding: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.025))
            Divider()
            content.padding(contentPadding)
        }
        .linearPanel()
    }
}

private struct SectionTitle: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)
    }
}

private struct EmptyState: View {
    var icon: String
    var title: String
    var detail: String
    var buttonTitle: String?
    var action: (() -> Void)?

    init(icon: String, title: String, detail: String, buttonTitle: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon; self.title = title; self.detail = detail; self.buttonTitle = buttonTitle; self.action = action
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundColor(.secondary)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundColor(.secondary).multilineTextAlignment(.center)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .controlSize(.regular)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}

private extension View {
    func linearPanel() -> some View {
        self
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppStyle.panelRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.panelRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
    }
}
