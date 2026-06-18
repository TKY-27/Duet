import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ToolbarView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.duetPalette) private var palette
    @Environment(\.appLanguage) private var language
    @AppStorage("duet.language") private var languageRaw = AppLanguage.systemDefault.rawValue
    @AppStorage("duet.roomViewMode") private var roomViewMode: RoomViewMode = .chat
    @State private var showingSetup = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                store.running ? store.stop() : store.resume()
            } label: {
                Label(store.running ? L10n.stop(language) : L10n.start(language), systemImage: store.running ? "stop.fill" : "play.fill")
            }
            .buttonStyle(PrimaryControlButtonStyle(tint: store.running ? palette.destructive : AgentID.claude.accent))

            Spacer(minLength: 12)

            RepoPill(repoPath: store.repoPath.isEmpty ? store.projectRoot.path : store.repoPath, branch: store.branchLabel)

            Spacer(minLength: 12)

            HubStatusBadge(state: store.connectionState)

            Button {
                showingSetup = true
            } label: {
                Image(systemName: "checklist")
            }
            .fixedSize()
            .help(L10n.setup(language))
            .accessibilityLabel(L10n.setup(language))
            .popover(isPresented: $showingSetup, arrowEdge: .bottom) {
                SetupView()
            }

            Menu {
                ForEach(TranscriptExporter.Format.allCases) { format in
                    Button(format.rawValue.capitalized) { export(format) }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(store.transcript.isEmpty)
            .help(L10n.export(language))
            .accessibilityLabel(L10n.export(language))

            Picker(L10n.language(language), selection: $languageRaw) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.shortLabel).tag(language.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(L10n.language(language))
            .frame(width: 128)

            Picker(L10n.viewMode(language), selection: $roomViewMode) {
                ForEach(RoomViewMode.allCases) { mode in
                    Image(systemName: mode.systemImage)
                        .accessibilityLabel(mode.accessibilityLabel(language))
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(L10n.viewMode(language))
            .frame(width: 88)

            Picker(L10n.theme(language), selection: $store.theme) {
                ForEach(DuetTheme.allCases) { theme in
                    Image(systemName: theme.systemImage)
                        .accessibilityLabel(theme.accessibilityLabel)
                        .tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(L10n.theme(language))
            .frame(width: 112)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(palette.toolbar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }

    private func export(_ format: TranscriptExporter.Format) {
        guard let data = store.exportData(format: format, language: language) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "duet-transcript.\(format.fileExtension)"
        if let type = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            store.noteUserFacingError(L10n.exportFailed(language))
        }
    }
}

private struct RepoPill: View {
    @Environment(\.duetPalette) private var palette
    var repoPath: String
    var branch: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(palette.tertiaryText)
            Text(repoPath.abbreviatedPath)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(palette.text)
            Text("·")
                .foregroundStyle(palette.tertiaryText)
            Text(branch)
                .foregroundStyle(AgentID.codex.accent)
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(palette.mono)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.softBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: 420)
    }
}

private struct HubStatusBadge: View {
    @Environment(\.duetPalette) private var palette
    @Environment(\.appLanguage) private var language
    var state: ConnectionState

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(state.statusColor(in: palette))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text("Hub \(state.label(language: language))")
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(palette.secondaryText)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.softBorder, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel(language: language))
    }
}

struct PrimaryControlButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(tint.opacity(configuration.isPressed ? 0.80 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
