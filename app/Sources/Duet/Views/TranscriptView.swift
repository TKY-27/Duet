import SwiftUI

/// The conversation, set as a document rather than a chat.
///
/// The previous design used left/right chat bubbles with accent-tinted fills
/// and asymmetric corners — an iMessage impression that fought the content.
/// Agent coordination messages are prose with file references in them, often
/// several sentences long, interleaved with human interruptions and system
/// events. That reads best as one column with a speaker gutter, the way a
/// timeline or a well-set transcript does.
///
/// Speaker identity lives in the gutter (a coloured mark and a name), not in
/// the shape or fill of the text, so a long message and a one-line
/// acknowledgement look like the same kind of object.
struct TranscriptView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.appLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, message in
                        TranscriptEntry(
                            message: message,
                            isContinuation: isContinuation(at: index),
                            language: language
                        )
                        .id(message.id)
                    }
                }
                .padding(.vertical, DuetSpacing.loose)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .textSelection(.enabled)
            .background(DuetColor.contentBackground)
            .onChange(of: entries.count) { _, _ in
                guard let lastID = entries.last?.id else { return }
                withAnimation(DuetMotion.respectingReduceMotion(DuetMotion.messageArrival, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
            .overlay {
                if entries.isEmpty {
                    TranscriptEmptyState()
                }
            }
        }
    }

    private var entries: [BusMessage] {
        store.visibleTranscript
    }

    /// Consecutive messages from the same speaker drop their header, so a
    /// back-and-forth reads as a conversation rather than a stack of cards.
    private func isContinuation(at index: Int) -> Bool {
        guard index > 0 else { return false }
        let current = entries[index]
        let previous = entries[index - 1]
        guard current.kind != "system", previous.kind != "system" else { return false }
        guard current.from == previous.from, current.to == previous.to else { return false }
        // A gap in time is a new thought even from the same speaker.
        return current.createdAt.timeIntervalSince(previous.createdAt) < 120
    }
}

private struct TranscriptEntry: View {
    var message: BusMessage
    var isContinuation: Bool
    var language: AppLanguage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            gutter
            content
            Spacer(minLength: 0)
        }
        .padding(.top, isContinuation ? DuetSpacing.hairline : DuetSpacing.regular)
        .padding(.bottom, DuetSpacing.hairline)
        .padding(.horizontal, DuetSpacing.loose)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var gutter: some View {
        VStack(alignment: .trailing, spacing: DuetSpacing.hairline) {
            if !isContinuation {
                Text(DuetFormatters.messageTime.string(from: message.createdAt))
                    .font(DuetFont.mono)
                    .foregroundStyle(DuetColor.tertiaryText)
                    .monospacedDigit()
            }
        }
        .frame(width: DuetSpacing.gutter, alignment: .trailing)
        .padding(.trailing, DuetSpacing.regular)
    }

    @ViewBuilder
    private var content: some View {
        switch speaker {
        case .agent(let agent):
            VStack(alignment: .leading, spacing: DuetSpacing.hairline) {
                if !isContinuation {
                    AgentSpeakerHeader(agent: agent, message: message, language: language)
                }
                Text(message.message)
                    .font(DuetFont.body)
                    .foregroundStyle(DuetColor.primaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: DuetSpacing.readingMeasure, alignment: .leading)

        case .human:
            // The human's own words get a rule in their accent colour. It is
            // the only vertical rule in the transcript, so an interruption is
            // findable by scrolling rather than by reading.
            HStack(alignment: .top, spacing: DuetSpacing.regular) {
                Rectangle()
                    .fill(DuetColor.human)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: DuetSpacing.hairline) {
                    if !isContinuation {
                        Text(L10n.humanLabel(language, recipient: message.recipientDisplayName(language: language)))
                            .font(DuetFont.speaker)
                            .foregroundStyle(DuetColor.human)
                    }
                    Text(message.message)
                        .font(DuetFont.body)
                        .foregroundStyle(DuetColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: DuetSpacing.readingMeasure, alignment: .leading)

        case .system:
            Text(message.message)
                .font(DuetFont.meta)
                .foregroundStyle(DuetColor.tertiaryText)
                .frame(maxWidth: DuetSpacing.readingMeasure, alignment: .leading)
        }
    }

    private enum Speaker {
        case agent(AgentID)
        case human
        case system
    }

    private var speaker: Speaker {
        if message.kind == "human" || message.from == "human" { return .human }
        if let agent = message.fromAgent { return .agent(agent) }
        return .system
    }

    private var accessibilityLabel: String {
        let time = DuetFormatters.messageTime.string(from: message.createdAt)
        switch speaker {
        case .agent(let agent):
            return "\(agent.displayName), \(time). \(message.message)"
        case .human:
            return "\(L10n.humanLabel(language, recipient: message.recipientDisplayName(language: language))), \(time). \(message.message)"
        case .system:
            return "\(time). \(message.message)"
        }
    }
}

private struct AgentSpeakerHeader: View {
    var agent: AgentID
    var message: BusMessage
    var language: AppLanguage

    var body: some View {
        HStack(spacing: DuetSpacing.tight) {
            StatusDot(color: agent.accent, filled: true, size: 8)
            Text(agent.displayName)
                .font(DuetFont.speaker)
                .foregroundStyle(DuetColor.primaryText)
            if message.to == "human" {
                Text(L10n.toHuman(language))
                    .font(DuetFont.meta)
                    .foregroundStyle(DuetColor.human)
            }
        }
    }
}

private struct TranscriptEmptyState: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(spacing: DuetSpacing.tight) {
            Text(title)
                .font(DuetFont.emptyTitle)
                .foregroundStyle(DuetColor.secondaryText)
            Text(detail)
                .font(DuetFont.meta)
                .foregroundStyle(DuetColor.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .padding(DuetSpacing.section)
        .accessibilityElement(children: .combine)
    }

    /// The empty state is written for the situation the user is actually in.
    /// A single "no messages yet" for every case is the tell of a UI where
    /// nobody thought about the unhappy paths.
    private var title: String {
        if !store.connectionState.isConnected { return L10n.emptyDisconnectedTitle(language) }
        if !store.running { return L10n.emptyStoppedTitle(language) }
        if !store.presence.claude.everSeen && !store.presence.codex.everSeen {
            return L10n.emptyNoAgentsTitle(language)
        }
        return L10n.emptyLog(language)
    }

    private var detail: String {
        if !store.connectionState.isConnected { return L10n.emptyDisconnectedDetail(language) }
        if !store.running { return L10n.emptyStoppedDetail(language) }
        if !store.presence.claude.everSeen && !store.presence.codex.everSeen {
            return L10n.emptyNoAgentsDetail(language)
        }
        return L10n.emptyLogDetail(language)
    }
}
