import AppKit
import SwiftUI

/// The window.
///
/// This is a real `NavigationSplitView` with a real `.toolbar` and a real
/// `.inspector`, replacing a hand-built `VStack` of fake chrome. The practical
/// difference is that the sidebar, toolbar, and inspector now get the system's
/// materials, collapse behaviour, keyboard handling, and full-size-content
/// window treatment instead of approximations of them.
struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showInspector = true
    @State private var showSetup = false
    @State private var searchText = ""
    @State private var activeSenders: Set<String> = []
    @AppStorage("duet.language") private var languageRaw = AppLanguage.systemDefault.rawValue
    @AppStorage("duet.transcriptDensity") private var densityRaw = TranscriptDensity.comfortable.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .systemDefault
    }

    /// An empty `activeSenders` means "show everyone", so toggling the last
    /// sender off clears the filter rather than hiding the whole transcript.
    private func senderBinding(_ sender: String) -> Binding<Bool> {
        Binding {
            activeSenders.contains(sender)
        } set: { isOn in
            if isOn { activeSenders.insert(sender) } else { activeSenders.remove(sender) }
        }
    }

    /// Writes the transcript through a save panel. The panel is the only part
    /// that belongs in the view; the rendering lives in `TranscriptExporter`.
    private func export(_ format: TranscriptExporter.Format) {
        guard let data = store.exportData(format: format, language: language) else {
            store.noteUserFacingError(L10n.exportFailed(language))
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "duet-transcript.\(format == .markdown ? "md" : "json")"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            store.noteUserFacingError(L10n.exportFailed(language))
        }
    }

    var body: some View {
        NavigationSplitView {
            SessionSidebar()
                // HIG range for a source list; below ~220 the session titles
                // stop being readable at larger text sizes.
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            VStack(spacing: 0) {
                if store.isViewingArchivedSession {
                    ArchivedSessionBanner(language: language)
                }
                TranscriptView(searchText: searchText, activeSenders: $activeSenders)
                ComposerView()
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: L10n.searchPlaceholder(language))
            .navigationTitle("Duet")
            .navigationSubtitle(subtitle)
            .toolbar { toolbarContent }
        }
        .inspector(isPresented: $showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .environment(\.appLanguage, language)
    }

    /// The window subtitle carries the two facts a user checks constantly:
    /// which repository, and which branch. Both come from Git now, so an empty
    /// branch means "could not read" rather than a hardcoded placeholder.
    private var subtitle: String {
        let path = (store.repoPath.isEmpty ? store.projectRoot.path : store.repoPath).abbreviatedPath
        let branch = store.branchLabel
        return branch.isEmpty ? path : "\(path) — \(branch)"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                store.running ? store.stop() : store.resume()
            } label: {
                Label(
                    store.running ? L10n.stop(language) : L10n.start(language),
                    systemImage: store.running ? "stop.fill" : "play.fill"
                )
            }
            .disabled(!store.connectionState.isConnected)
        }

        ToolbarItem {
            HubStatusIndicator(state: store.connectionState, language: language)
        }

        ToolbarItem {
            Button {
                Task { await store.startNewSession() }
            } label: {
                Label(L10n.newSession(language), systemImage: "plus")
            }
            .disabled(!store.connectionState.isConnected)
        }

        ToolbarItem {
            Picker(L10n.viewMode(language), selection: $densityRaw) {
                ForEach(TranscriptDensity.allCases) { density in
                    Label(density.accessibilityLabel(language), systemImage: density.systemImage)
                        .tag(density.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(L10n.viewMode(language))
        }

        ToolbarItem {
            Menu {
                ForEach(AgentID.allCases) { agent in
                    Toggle(agent.displayName, isOn: senderBinding(agent.rawValue))
                }
                Toggle(L10n.humanShort(language), isOn: senderBinding("human"))
                Divider()
                Button(L10n.clearFilter(language)) { activeSenders.removeAll() }
                    .disabled(activeSenders.isEmpty)
            } label: {
                Label(L10n.filter(language), systemImage: activeSenders.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
        }

        ToolbarItem {
            Button {
                showSetup.toggle()
            } label: {
                Label(L10n.setup(language), systemImage: "gearshape")
            }
            .popover(isPresented: $showSetup, arrowEdge: .bottom) {
                SetupView().environment(\.appLanguage, language)
            }
        }

        ToolbarItem {
            Menu {
                Button("Markdown") { export(.markdown) }
                Button("JSON") { export(.json) }
            } label: {
                Label(L10n.export(language), systemImage: "square.and.arrow.up")
            }
            .disabled(store.visibleTranscript.isEmpty)
        }

        // Inspector toggle is the trailing-most item, per macOS convention.
        ToolbarItem {
            Button {
                showInspector.toggle()
            } label: {
                Label(L10n.toggleInspector(language), systemImage: "sidebar.trailing")
            }
            .accessibilityLabel(L10n.toggleInspector(language))
        }
    }
}

private struct HubStatusIndicator: View {
    var state: ConnectionState
    var language: AppLanguage

    var body: some View {
        HStack(spacing: DuetSpacing.hairline) {
            StatusDot(color: state.statusColor, filled: state.isConnected)
            Text(state.label(language: language))
                .font(DuetFont.meta)
                .foregroundStyle(DuetColor.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel(language: language))
    }
}

/// Reading history is a different mode from watching a live run, so it says so
/// and offers the way back rather than relying on the sidebar selection alone.
private struct ArchivedSessionBanner: View {
    @EnvironmentObject private var store: AppStore
    var language: AppLanguage

    var body: some View {
        HStack(spacing: DuetSpacing.tight) {
            Image(systemName: "clock.arrow.circlepath")
            Text(L10n.archivedBannerTitle(language))
            Spacer()
            Button(L10n.backToLive(language)) {
                store.showLiveSession()
            }
            .buttonStyle(.link)
        }
        .font(DuetFont.meta)
        .foregroundStyle(DuetColor.secondaryText)
        .padding(.horizontal, DuetSpacing.loose)
        .padding(.vertical, DuetSpacing.tight)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }
}
