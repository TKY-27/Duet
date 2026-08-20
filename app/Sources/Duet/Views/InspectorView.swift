import SwiftUI

/// Roles, agent presence, repository state, and diagnostics.
///
/// This is a real `.inspector`, not a hand-built panel: it gets the system's
/// width behaviour, its material, and its collapse animation for free, and the
/// toolbar toggle sits where macOS users expect it (trailing-most).
struct InspectorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.appLanguage) private var language
    @State private var draftRoles: Roles?

    private var rolesBinding: Binding<Roles> {
        Binding {
            draftRoles ?? store.roles
        } set: { next in
            draftRoles = next
        }
    }

    private var validationIssues: [RoleValidationIssue] {
        RoleValidator.issues(for: rolesBinding.wrappedValue, language: language)
    }

    private var hasUnappliedEdits: Bool {
        draftRoles != nil && draftRoles != store.roles
    }

    var body: some View {
        Form {
            Section(L10n.agents(language)) {
                ForEach(AgentID.allCases) { agent in
                    AgentRoleRow(
                        agent: agent,
                        role: roleBinding(for: agent),
                        presence: store.presence[agent],
                        stall: store.stalls[agent],
                        queued: agent == .claude ? store.queues.claude : store.queues.codex,
                        running: store.running,
                        roleIssue: RoleValidator.issue(for: agent, field: .role, in: rolesBinding.wrappedValue, language: language),
                        taskIssue: RoleValidator.issue(for: agent, field: .task, in: rolesBinding.wrappedValue, language: language),
                        language: language
                    )
                }

                Button {
                    let nextRoles = rolesBinding.wrappedValue
                    Task {
                        if await store.setRoles(nextRoles) { draftRoles = nil }
                    }
                } label: {
                    Text(L10n.applyRoles(language)).frame(maxWidth: .infinity)
                }
                .disabled(!validationIssues.isEmpty || !store.connectionState.isConnected || !hasUnappliedEdits)
                .accessibilityLabel(L10n.applyRolesAccessibility(language))
            }

            Section(L10n.repository(language)) {
                RepositorySection(repo: store.repo, repoPath: store.repoPath, language: language)
            }

            Section(L10n.session(language)) {
                LabeledContent("hold", value: "\(store.holdSec)s")
                LabeledContent("no-progress", value: "\(store.noProgressHoldSec)s")
                LabeledContent("progress", value: "\(store.progressIntervalSec)s")
                LabeledContent("Hub", value: store.connectionState.label(language: language))
                    .foregroundStyle(store.connectionState.statusColor)
            }
            .font(DuetFont.mono)

            if store.lastError != nil || store.hubOutput.latestStderr != nil {
                Section(L10n.diagnostics(language)) {
                    if let lastError = store.lastError {
                        DiagnosticText(title: "Error", message: lastError)
                    }
                    if let latestStderr = store.hubOutput.latestStderr {
                        DiagnosticText(title: "Hub stderr", message: latestStderr)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: store.roles) { _, newValue in
            // Only discard the draft when the user has nothing in flight,
            // so a Hub echo cannot wipe half-typed task text.
            if !hasUnappliedEdits { draftRoles = newValue }
        }
    }

    private func roleBinding(for agent: AgentID) -> Binding<RoleAssignment> {
        Binding {
            rolesBinding.wrappedValue[agent]
        } set: { next in
            var roles = rolesBinding.wrappedValue
            roles[agent] = next
            rolesBinding.wrappedValue = roles
        }
    }
}

private struct AgentRoleRow: View {
    var agent: AgentID
    @Binding var role: RoleAssignment
    var presence: AgentPresence
    var stall: AgentStall
    var queued: Int
    var running: Bool
    var roleIssue: RoleValidationIssue?
    var taskIssue: RoleValidationIssue?
    var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: DuetSpacing.tight) {
            HStack(spacing: DuetSpacing.tight) {
                AgentAvatar(agent: agent, size: 22)
                Text(agent.displayName)
                    .font(DuetFont.speaker)
                Spacer()
                HStack(spacing: DuetSpacing.hairline) {
                    StatusDot(
                        color: presence.connected ? DuetColor.success : DuetColor.tertiaryText,
                        filled: presence.connected
                    )
                    Text(presence.connected ? L10n.connected(language) : L10n.notConnected(language))
                        .font(DuetFont.meta)
                        .foregroundStyle(DuetColor.secondaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(agent.displayName): \(presence.connected ? L10n.connected(language) : L10n.notConnected(language))")
            }

            if running, queued > 0 {
                Text(L10n.queued(language, count: queued))
                    .font(DuetFont.meta)
                    .foregroundStyle(DuetColor.secondaryText)
            }

            if running, stall.stalled {
                Label(L10n.possibleStall(language, seconds: stall.sinceSeconds), systemImage: "exclamationmark.triangle")
                    .font(DuetFont.meta)
                    .foregroundStyle(DuetColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: DuetSpacing.hairline) {
                Text(L10n.role(language)).fieldLabelStyle()
                TextField(L10n.role(language), text: $role.role)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .accessibilityLabel("\(agent.displayName) \(L10n.role(language))")
                if let roleIssue {
                    Text(roleIssue.message).font(DuetFont.meta).foregroundStyle(DuetColor.failure)
                }
            }

            VStack(alignment: .leading, spacing: DuetSpacing.hairline) {
                Text(L10n.task(language)).fieldLabelStyle()
                TextEditor(text: $role.task)
                    .font(DuetFont.body)
                    .frame(minHeight: 64)
                    .scrollContentBackground(.hidden)
                    .padding(DuetSpacing.hairline)
                    .background(DuetColor.contentBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(taskIssue == nil ? DuetColor.separator : DuetColor.failure)
                    )
                    .accessibilityLabel("\(agent.displayName) \(L10n.task(language))")
                if let taskIssue {
                    Text(taskIssue.message).font(DuetFont.meta).foregroundStyle(DuetColor.failure)
                }
            }
        }
        .padding(.vertical, DuetSpacing.hairline)
    }
}

private struct RepositorySection: View {
    var repo: RepoStatus
    var repoPath: String
    var language: AppLanguage

    var body: some View {
        if repo.available {
            LabeledContent(L10n.branch(language)) {
                Text(repo.branch).font(DuetFont.mono)
            }
            if repo.ahead > 0 || repo.behind > 0 {
                LabeledContent("ahead / behind") {
                    Text("\(repo.ahead) / \(repo.behind)").font(DuetFont.mono).monospacedDigit()
                }
            }
            LabeledContent(L10n.repository(language, changedFiles: repo.files.count)) {
                Text("+\(repo.totalAdded) −\(repo.totalRemoved)")
                    .font(DuetFont.mono)
                    .monospacedDigit()
                    .foregroundStyle(DuetColor.secondaryText)
            }
            ForEach(repo.files.prefix(12)) { file in
                HStack(spacing: DuetSpacing.tight) {
                    Text(file.status)
                        .font(DuetFont.mono)
                        .foregroundStyle(DuetColor.tertiaryText)
                        .frame(width: 24, alignment: .leading)
                    Text(file.fileName)
                        .font(DuetFont.mono)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(file.path)
                    Spacer()
                    Text("+\(file.added) −\(file.removed)")
                        .font(DuetFont.mono)
                        .monospacedDigit()
                        .foregroundStyle(DuetColor.tertiaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(file.path), +\(file.added) −\(file.removed)")
            }
            if repo.truncated {
                Text("…").font(DuetFont.meta).foregroundStyle(DuetColor.tertiaryText)
            }
        } else {
            VStack(alignment: .leading, spacing: DuetSpacing.hairline) {
                Text(L10n.repoUnavailable(language))
                    .font(DuetFont.meta)
                    .foregroundStyle(DuetColor.secondaryText)
                if !repoPath.isEmpty {
                    Text(repoPath.abbreviatedPath)
                        .font(DuetFont.mono)
                        .foregroundStyle(DuetColor.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}

private struct DiagnosticText: View {
    var title: String
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: DuetSpacing.hairline) {
            Text(title).font(DuetFont.fieldLabel).foregroundStyle(DuetColor.failure)
            Text(message)
                .font(DuetFont.mono)
                .foregroundStyle(DuetColor.secondaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(message)")
    }
}
