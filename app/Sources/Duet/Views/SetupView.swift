import AppKit
import SwiftUI

/// Registration commands and role prompts, ready to paste into each agent.
///
/// Behaviour and the security model are unchanged from the original: tokens are
/// fetched from the Hub's control-token-gated `/setup` endpoint, never over the
/// control WebSocket the transcript flows on, and never rendered on screen —
/// they exist only inside the command that goes to the pasteboard.
///
/// Restyled onto the shared design system: system semantic colours, the named
/// type scale, and standard button styles, so it matches the rest of the window
/// and picks up appearance and contrast settings.
struct SetupView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.appLanguage) private var language
    @State private var setup: DuetSetupInfo?
    @State private var prompts: [AgentID: String] = [:]
    @State private var isLoading = true
    @State private var copiedLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DuetSpacing.regular) {
            VStack(alignment: .leading, spacing: DuetSpacing.hairline) {
                Text(L10n.setupTitle(language))
                    .font(DuetFont.emptyTitle)
                Text(L10n.setupIntro(language))
                    .font(DuetFont.meta)
                    .foregroundStyle(DuetColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let setup {
                section(agent: .claude, command: setup.claudeCommand)
                section(agent: .codex, command: setup.codexCommand)
            } else {
                Label(L10n.setupUnavailable(language), systemImage: "exclamationmark.triangle")
                    .font(DuetFont.meta)
                    .foregroundStyle(DuetColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let copiedLabel {
                Label("\(copiedLabel) — \(L10n.copied(language))", systemImage: "checkmark.circle.fill")
                    .font(DuetFont.meta)
                    .foregroundStyle(DuetColor.success)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(DuetSpacing.loose)
        .frame(width: 400)
        .task { await load() }
    }

    @ViewBuilder
    private func section(agent: AgentID, command: String) -> some View {
        VStack(alignment: .leading, spacing: DuetSpacing.tight) {
            HStack(spacing: DuetSpacing.tight) {
                AgentAvatar(agent: agent, size: 20)
                Text(agent.displayName).font(DuetFont.speaker)
                Text(agent.subtitle)
                    .font(DuetFont.meta)
                    .foregroundStyle(DuetColor.tertiaryText)
                Spacer()
                StatusDot(
                    color: store.presence[agent].connected ? DuetColor.success : DuetColor.tertiaryText,
                    filled: store.presence[agent].connected
                )
            }
            HStack(spacing: DuetSpacing.tight) {
                Button {
                    copy(command, label: "\(agent.displayName) \(L10n.registrationWord(language))")
                } label: {
                    Label(L10n.copyRegistration(language), systemImage: "terminal")
                }
                if let prompt = prompts[agent] {
                    Button {
                        copy(prompt, label: "\(agent.displayName) \(L10n.promptWord(language))")
                    } label: {
                        Label(L10n.copyPrompt(language), systemImage: "doc.on.doc")
                    }
                }
            }
            .font(DuetFont.meta)
        }
        .padding(DuetSpacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DuetColor.contentBackground, in: .rect(cornerRadius: 8))
        .overlay(alignment: .leading) {
            // The one decorative use of agent colour in the app, and it is
            // identity: which agent this block configures.
            Rectangle().fill(agent.accent).frame(width: 3)
                .clipShape(.rect(topLeadingRadius: 8, bottomLeadingRadius: 8))
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DuetColor.separator))
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
