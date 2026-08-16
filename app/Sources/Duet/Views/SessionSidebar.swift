import SwiftUI

/// Session history. The live session is pinned first and always selectable, so
/// reading an archived session is never a one-way trip.
struct SessionSidebar: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.appLanguage) private var language

    var body: some View {
        List(selection: selection) {
            Section(L10n.sessions(language)) {
                LiveSessionRow(
                    messageCount: store.transcript.count,
                    running: store.running,
                    language: language
                )
                .tag(SessionSelection.live)

                ForEach(archivedSessions) { session in
                    ArchivedSessionRow(session: session, language: language)
                        .tag(SessionSelection.archived(session.id))
                }
            }

            if archivedSessions.isEmpty {
                Text(L10n.noSessions(language))
                    .font(DuetFont.meta)
                    .foregroundStyle(DuetColor.tertiaryText)
            }
        }
        .listStyle(.sidebar)
        .task {
            await store.refreshSessions()
        }
    }

    /// Archived sessions exclude the one currently being written, which is
    /// already represented by the pinned live row.
    private var archivedSessions: [SessionSummary] {
        store.sessions.filter { $0.id != store.currentSessionId }
    }

    private var selection: Binding<SessionSelection?> {
        Binding {
            store.viewingSessionId.map(SessionSelection.archived) ?? .live
        } set: { next in
            switch next {
            case .live, .none:
                store.showLiveSession()
            case .archived(let id):
                Task { await store.openSession(id) }
            }
        }
    }
}

enum SessionSelection: Hashable {
    case live
    case archived(String)
}

private struct LiveSessionRow: View {
    var messageCount: Int
    var running: Bool
    var language: AppLanguage

    var body: some View {
        HStack(spacing: DuetSpacing.tight) {
            StatusDot(color: running ? DuetColor.success : DuetColor.tertiaryText, filled: running)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.liveSession(language))
                Text(L10n.messageCount(language, count: messageCount))
                    .font(DuetFont.meta)
                    .foregroundStyle(DuetColor.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ArchivedSessionRow: View {
    var session: SessionSummary
    var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(session.title.isEmpty ? session.id : session.title)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: DuetSpacing.hairline) {
                Text(DuetFormatters.sessionDate.string(from: session.startedAt))
                Text("·")
                Text(L10n.messageCount(language, count: session.messageCount))
            }
            .font(DuetFont.meta)
            .foregroundStyle(DuetColor.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}
