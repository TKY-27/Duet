import AppKit
import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.duetPalette) private var palette
    @Environment(\.appLanguage) private var language
    @State private var setup: DuetSetupInfo?
    @State private var prompts: [AgentID: String] = [:]
    @State private var isLoading = true
    @State private var copiedLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.setupTitle(language))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(palette.text)
            Text(L10n.setupIntro(language))
                .font(.system(size: 11.5))
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if isLoading {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let setup {
                section(agent: .claude, command: setup.claudeCommand)
                section(agent: .codex, command: setup.codexCommand)
            } else {
                Text(L10n.setupUnavailable(language))
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let copiedLabel {
                Label("\(copiedLabel) — \(L10n.copied(language))", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.success)
            }
        }
        .padding(18)
        .frame(width: 380)
        .background(palette.panel)
        .task { await load() }
    }

    @ViewBuilder
    private func section(agent: AgentID, command: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                AgentAvatar(agent: agent, size: 20)
                Text(agent.displayName)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(agent.accent)
                Text(agent.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.tertiaryText)
            }
            HStack(spacing: 8) {
                copyButton(L10n.copyRegistration(language), systemImage: "terminal") {
                    copy(command, label: "\(agent.displayName) \(L10n.registrationWord(language))")
                }
                if let prompt = prompts[agent] {
                    copyButton(L10n.copyPrompt(language), systemImage: "doc.on.doc") {
                        copy(prompt, label: "\(agent.displayName) \(L10n.promptWord(language))")
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card)
        .overlay(alignment: .leading) { Rectangle().fill(agent.accent).frame(width: 3) }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.softBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func copyButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(palette.elevated)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func copy(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedLabel = label
    }

    @MainActor
    private func load() async {
        isLoading = true
        // Read the role prompts from disk once here rather than in `body`, which can be
        // re-evaluated frequently.
        var loaded: [AgentID: String] = [:]
        for agent in AgentID.allCases {
            if let prompt = store.rolePrompt(for: agent, language: language) {
                loaded[agent] = prompt
            }
        }
        prompts = loaded
        setup = await store.fetchSetup()
        isLoading = false
    }
}
