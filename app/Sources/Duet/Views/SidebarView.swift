import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.duetPalette) private var palette
    @Environment(\.appLanguage) private var language
    @State private var draftRoles: Roles?
    @State private var remoteRolesChanged = false

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(L10n.roleAssignment(language))
                AgentRoleCard(
                    agent: .claude,
                    role: roleBinding(for: .claude),
                    status: status(for: .claude),
                    stallWarning: stallWarning(for: .claude),
                    roleIssue: RoleValidator.issue(for: .claude, field: .role, in: rolesBinding.wrappedValue, language: language),
                    taskIssue: RoleValidator.issue(for: .claude, field: .task, in: rolesBinding.wrappedValue, language: language)
                )
                AgentRoleCard(
                    agent: .codex,
                    role: roleBinding(for: .codex),
                    status: status(for: .codex),
                    stallWarning: stallWarning(for: .codex),
                    roleIssue: RoleValidator.issue(for: .codex, field: .role, in: rolesBinding.wrappedValue, language: language),
                    taskIssue: RoleValidator.issue(for: .codex, field: .task, in: rolesBinding.wrappedValue, language: language)
                )

                if !validationIssues.isEmpty {
                    ValidationSummary(issues: validationIssues)
                }

                if remoteRolesChanged {
                    RemoteRolesChangedNotice {
                        draftRoles = nil
                        remoteRolesChanged = false
                    }
                }

                Button {
                    let nextRoles = rolesBinding.wrappedValue
                    Task {
                        if await store.setRoles(nextRoles) {
                            draftRoles = nil
                            remoteRolesChanged = false
                        }
                    }
                } label: {
                    Label(L10n.applyRoles(language), systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SidebarActionButtonStyle())
                .disabled(!validationIssues.isEmpty || !store.connectionState.isConnected)
                .accessibilityLabel(L10n.applyRolesAccessibility(language))
                .padding(.horizontal, 12)
                .padding(.top, 2)

                SectionLabel(L10n.session(language))
                MetaRows(
                    rows: [
                        (L10n.repository(language), (store.repoPath.isEmpty ? store.projectRoot.path : store.repoPath).abbreviatedPath),
                        (L10n.branch(language), store.branchLabel),
                        ("Hub", store.connectionState.label(language: language)),
                        ("hold", "\(store.holdSec)s"),
                        ("no-progress", "\(store.noProgressHoldSec)s"),
                        ("progress", "\(store.progressIntervalSec)s"),
                    ],
                    hubState: store.connectionState
                )

                if let lastError = store.lastError {
                    DiagnosticText(title: "Error", message: lastError)
                }

                if let latestStderr = store.hubOutput.latestStderr {
                    DiagnosticText(title: "Hub stderr", message: latestStderr)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 286)
        .background(palette.panel)
        .overlay(alignment: .trailing) {
            Rectangle().fill(palette.border).frame(width: 1)
        }
        .onChange(of: store.roles) { _, newValue in
            // Don't clobber unsaved edits. draftRoles is nil only when the panel is in sync
            // with the Hub; in that case rolesBinding already falls back to store.roles.
            if draftRoles == nil || draftRoles == newValue {
                draftRoles = nil
                remoteRolesChanged = false
            } else {
                // Roles changed remotely while the user was editing — flag it instead of
                // silently overwriting their input.
                remoteRolesChanged = true
            }
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

    private func status(for agent: AgentID) -> String {
        if !store.running { return L10n.stopped(language) }
        let queue = agent == .claude ? store.queues.claude : store.queues.codex
        if queue > 0 { return L10n.queued(language, count: queue) }
        if store.transcript.last?.from == agent.rawValue { return L10n.completed(language) }
        return L10n.waiting(language)
    }

    private func stallWarning(for agent: AgentID) -> String? {
        guard store.running else { return nil }
        let stall = store.stalls[agent]
        guard stall.stalled else { return nil }
        return L10n.possibleStall(language, seconds: stall.sinceSeconds)
    }
}

private struct SectionLabel: View {
    @Environment(\.duetPalette) private var palette
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(palette.tertiaryText)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }
}

private struct AgentRoleCard: View {
    @Environment(\.duetPalette) private var palette
    @Environment(\.appLanguage) private var language
    var agent: AgentID
    @Binding var role: RoleAssignment
    var status: String
    var stallWarning: String?
    var roleIssue: RoleValidationIssue?
    var taskIssue: RoleValidationIssue?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                AgentAvatar(agent: agent, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.displayName)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(agent.accent)
                    Text(agent.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.tertiaryText)
                }
                Spacer()
                Text(status)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(palette.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(palette.mono)
                    .clipShape(Capsule())
            }
            if let stallWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(stallWarning)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(palette.warning)
                .accessibilityLabel(stallWarning)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.role(language)).fieldLabelStyle()
                TextField("role", text: $role.role)
                    .textFieldStyle(DuetTextFieldStyle())
                    .accessibilityLabel("\(agent.displayName) role")
                if let roleIssue {
                    IssueText(roleIssue.message)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.task(language)).fieldLabelStyle()
                TextEditor(text: $role.task)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 68)
                    .background(palette.input)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(taskIssue == nil ? palette.border : palette.destructive, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel("\(agent.displayName) task")
                if let taskIssue {
                    IssueText(taskIssue.message)
                }
            }
        }
        .padding(12)
        .background(palette.card)
        .overlay(alignment: .leading) {
            Rectangle().fill(agent.accent).frame(width: 3)
        }
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(palette.softBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

private struct MetaRows: View {
    @Environment(\.duetPalette) private var palette
    var rows: [(String, String)]
    var hubState: ConnectionState

    var body: some View {
        VStack(spacing: 7) {
            ForEach(rows, id: \.0) { key, value in
                HStack(alignment: .firstTextBaseline) {
                    Text(key)
                        .foregroundStyle(palette.tertiaryText)
                    Spacer(minLength: 10)
                    Text(value)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(key == "Hub" ? hubState.statusColor(in: palette) : palette.secondaryText)
                        .font(.system(size: 11.5, design: .monospaced))
                }
                .font(.system(size: 11.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

private struct ValidationSummary: View {
    @Environment(\.duetPalette) private var palette
    @Environment(\.appLanguage) private var language
    var issues: [RoleValidationIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(issues) { issue in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(issue.message)
                }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(palette.destructive)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .accessibilityLabel(L10n.roleInputError(language))
    }
}

private struct RemoteRolesChangedNotice: View {
    @Environment(\.duetPalette) private var palette
    @Environment(\.appLanguage) private var language
    var onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10))
                Text(L10n.rolesUpdatedRemotely(language))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onDiscard) {
                Text(L10n.discardLocalEdits(language))
                    .font(.system(size: 10.5, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.human)
        }
        .font(.system(size: 11))
        .foregroundStyle(palette.warning)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct IssueText: View {
    @Environment(\.duetPalette) private var palette
    var message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.system(size: 10.5))
            .foregroundStyle(palette.destructive)
    }
}

private struct DiagnosticText: View {
    @Environment(\.duetPalette) private var palette
    var title: String
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(palette.destructive)
            Text(message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.destructive)
                .textSelection(.enabled)
        }
        .padding(12)
        .accessibilityLabel("\(title): \(message)")
    }
}

private struct SidebarActionButtonStyle: ButtonStyle {
    @Environment(\.duetPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(palette.text)
            .padding(.vertical, 8)
            .background(palette.elevated.opacity(configuration.isPressed ? 0.75 : 1))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension Text {
    func fieldLabelStyle() -> some View {
        modifier(FieldLabelModifier())
    }
}

private struct FieldLabelModifier: ViewModifier {
    @Environment(\.duetPalette) private var palette

    func body(content: Content) -> some View {
        content
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(palette.tertiaryText)
    }
}

struct DuetTextFieldStyle: TextFieldStyle {
    @Environment(\.duetPalette) private var palette

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(palette.input)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct AgentAvatar: View {
    var agent: AgentID
    var size: CGFloat

    var body: some View {
        ZStack {
            if let iconImage {
                Image(nsImage: iconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(agent.accent)
                Text(String(agent.displayName.prefix(1)))
                    .font(.system(size: size * 0.42, weight: .black))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityLabel(agent.displayName)
    }

    private var iconImage: NSImage? {
        guard let url = Bundle.module.url(
            forResource: agent.iconResourceName,
            withExtension: "png",
            subdirectory: "Resources/AgentIcons"
        ) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
