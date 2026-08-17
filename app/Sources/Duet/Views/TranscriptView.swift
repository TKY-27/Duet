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
    @AppStorage("duet.transcriptDensity") private var densityRaw = TranscriptDensity.comfortable.rawValue
    /// Free-text filter, driven by the window's search field.
    var searchText: String = ""
    /// Per-sender filter. Empty means "show everyone".
    @Binding var activeSenders: Set<String>
    @State private var isPinnedToBottom = true
    @State private var lastSeenSeq = 0

    private var density: TranscriptDensity {
        TranscriptDensity(rawValue: densityRaw) ?? .comfortable
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, message in
                        if let daySeparator = daySeparator(at: index) {
                            DaySeparator(label: daySeparator)
                        }
                        TranscriptEntry(
                            message: message,
                            isContinuation: isContinuation(at: index),
                            density: density,
                            repoPath: store.repoPath,
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
                    TranscriptEmptyState(isFiltered: isFiltering)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isPinnedToBottom, unreadCount > 0 {
                    JumpToLatestButton(count: unreadCount, language: language) {
                        guard let lastID = entries.last?.id else { return }
                        withAnimation(DuetMotion.respectingReduceMotion(DuetMotion.messageArrival, reduceMotion: reduceMotion)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                        isPinnedToBottom = true
                        lastSeenSeq = entries.last?.seq ?? lastSeenSeq
                    }
                    .padding(DuetSpacing.loose)
                }
            }
            .onChange(of: entries.last?.seq) { _, newValue in
                if isPinnedToBottom { lastSeenSeq = newValue ?? lastSeenSeq }
            }
        }
    }

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !activeSenders.isEmpty
    }

    /// Messages newer than the last one the user actually saw at the bottom.
    private var unreadCount: Int {
        entries.filter { $0.seq > lastSeenSeq }.count
    }

    /// Client-side filter over the in-memory transcript by free text and/or sender.
    private var entries: [BusMessage] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = store.visibleTranscript
        guard !query.isEmpty || !activeSenders.isEmpty else { return all }
        return all.filter { message in
            if !activeSenders.isEmpty, !activeSenders.contains(message.from) { return false }
            guard !query.isEmpty else { return true }
            return message.message.lowercased().contains(query)
        }
    }

    /// Consecutive messages from the same speaker drop their header, so a
    /// back-and-forth reads as a conversation rather than a stack of cards.
    /// Compact mode keeps every header: scanning wants one uniform line each.
    private func isContinuation(at index: Int) -> Bool {
        guard density == .comfortable else { return false }
        guard index > 0 else { return false }
        let current = entries[index]
        let previous = entries[index - 1]
        guard current.kind != "system", previous.kind != "system" else { return false }
        guard current.from == previous.from, current.to == previous.to else { return false }
        // A gap in time is a new thought even from the same speaker.
        return current.createdAt.timeIntervalSince(previous.createdAt) < 120
    }

    /// A run that spans midnight is ambiguous without a date, and these runs
    /// routinely do. Returns a label only on the first entry of each day.
    private func daySeparator(at index: Int) -> String? {
        let current = entries[index]
        guard index > 0 else { return DuetFormatters.daySeparator.string(from: current.createdAt) }
        let previous = entries[index - 1]
        let calendar = Calendar.current
        guard !calendar.isDate(current.createdAt, inSameDayAs: previous.createdAt) else { return nil }
        return DuetFormatters.daySeparator.string(from: current.createdAt)
    }
}

private struct DaySeparator: View {
    var label: String

    var body: some View {
        HStack(spacing: DuetSpacing.regular) {
            Text(label)
                .font(DuetFont.meta)
                .foregroundStyle(DuetColor.tertiaryText)
            Rectangle()
                .fill(DuetColor.separator)
                .frame(height: 1)
        }
        .padding(.horizontal, DuetSpacing.loose)
        .padding(.top, DuetSpacing.loose)
        .padding(.bottom, DuetSpacing.tight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

private struct TranscriptEntry: View {
    var message: BusMessage
    var isContinuation: Bool
    var density: TranscriptDensity
    var repoPath: String
    var language: AppLanguage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            gutter
            content
            Spacer(minLength: 0)
        }
        .padding(.top, topPadding)
        .padding(.bottom, density == .compact ? 1 : DuetSpacing.hairline)
        .padding(.horizontal, DuetSpacing.loose)
        .help(DuetFormatters.fullTimestamp.string(from: message.createdAt))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var topPadding: CGFloat {
        switch density {
        case .compact: 1
        case .comfortable: isContinuation ? DuetSpacing.hairline : DuetSpacing.regular
        }
    }

    @ViewBuilder
    private var gutter: some View {
        VStack(alignment: .trailing, spacing: DuetSpacing.hairline) {
            if density == .compact {
                Text(DuetFormatters.logTime.string(from: message.createdAt))
                    .font(DuetFont.mono)
                    .foregroundStyle(DuetColor.tertiaryText)
                    .monospacedDigit()
            } else if !isContinuation {
                Text(DuetFormatters.messageTime.string(from: message.createdAt))
                    .font(DuetFont.mono)
                    .foregroundStyle(DuetColor.tertiaryText)
                    .monospacedDigit()
            }
        }
        .frame(width: DuetSpacing.gutter, alignment: .trailing)
        .padding(.trailing, DuetSpacing.regular)
    }

    /// Message body with repo-relative paths turned into openable links.
    /// `PathLinker` only links a token that resolves to a file inside
    /// `repoPath`, so message text can never open an arbitrary path.
    private var linkedMessage: AttributedString {
        PathLinker.attributedMessage(message.message, repoPath: repoPath)
    }

    @ViewBuilder
    private var content: some View {
        if density == .compact {
            compactContent
        } else {
            comfortableContent
        }
    }

    /// One line per message: speaker, then body, truncated. Built for scanning
    /// a long run, so it deliberately does not wrap.
    @ViewBuilder
    private var compactContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: DuetSpacing.tight) {
            switch speaker {
            case .agent(let agent):
                Text(agent.displayName)
                    .font(DuetFont.mono)
                    .foregroundStyle(agent.accent)
                    .frame(width: 56, alignment: .leading)
            case .human:
                Text(L10n.humanShort(language))
                    .font(DuetFont.mono)
                    .foregroundStyle(DuetColor.human)
                    .frame(width: 56, alignment: .leading)
            case .system:
                Text("hub")
                    .font(DuetFont.mono)
                    .foregroundStyle(DuetColor.tertiaryText)
                    .frame(width: 56, alignment: .leading)
            }
            Text(linkedMessage)
                .font(DuetFont.mono)
                .foregroundStyle(isSystem ? DuetColor.tertiaryText : DuetColor.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var isSystem: Bool {
        if case .system = speaker { return true }
        return false
    }

    @ViewBuilder
    private var comfortableContent: some View {
        switch speaker {
        case .agent(let agent):
            VStack(alignment: .leading, spacing: DuetSpacing.hairline) {
                if !isContinuation {
                    AgentSpeakerHeader(agent: agent, message: message, language: language)
                }
                Text(linkedMessage)
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
                    Text(linkedMessage)
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

private struct JumpToLatestButton: View {
    var count: Int
    var language: AppLanguage
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(L10n.jumpToLatestCount(language, count: count), systemImage: "arrow.down")
                .font(DuetFont.meta)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel(L10n.jumpToLatest(language))
    }
}

private struct TranscriptEmptyState: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.appLanguage) private var language
    var isFiltered: Bool

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
        // A filter that matches nothing is not the same situation as an empty
        // room, and saying "no agent has connected" there would be wrong.
        if isFiltered { return L10n.noSearchResults(language) }
        if !store.connectionState.isConnected { return L10n.emptyDisconnectedTitle(language) }
        if !store.running { return L10n.emptyStoppedTitle(language) }
        if !store.presence.claude.everSeen && !store.presence.codex.everSeen {
            return L10n.emptyNoAgentsTitle(language)
        }
        return L10n.emptyLog(language)
    }

    private var detail: String {
        if isFiltered { return L10n.noSearchResultsDetail(language) }
        if !store.connectionState.isConnected { return L10n.emptyDisconnectedDetail(language) }
        if !store.running { return L10n.emptyStoppedDetail(language) }
        if !store.presence.claude.everSeen && !store.presence.codex.everSeen {
            return L10n.emptyNoAgentsDetail(language)
        }
        return L10n.emptyLogDetail(language)
    }
}
