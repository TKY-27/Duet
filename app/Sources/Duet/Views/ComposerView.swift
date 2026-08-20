import SwiftUI

/// The human's way into the conversation.
///
/// Multi-line rather than a single-line field: an interruption is usually an
/// instruction, not a search query, and the old single-line `TextField` silently
/// made anything longer than the field unreadable while typing.
struct ComposerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.appLanguage) private var language
    @State private var recipient: Recipient = .both
    @State private var message = ""
    @State private var isSending = false
    @FocusState private var isFocused: Bool

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedMessage.isEmpty && store.connectionState.isConnected && !isSending
    }

    var body: some View {
        VStack(spacing: DuetSpacing.tight) {
            Divider()
            HStack(alignment: .bottom, spacing: DuetSpacing.regular) {
                VStack(alignment: .leading, spacing: DuetSpacing.hairline) {
                    Text(L10n.interruptTarget(language)).fieldLabelStyle()
                    Picker(L10n.recipient(language), selection: $recipient) {
                        ForEach(Recipient.allCases) { recipient in
                            Text(recipient.displayName(language: language)).tag(recipient)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                TextField(L10n.interruptPlaceholder(language), text: $message, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DuetFont.body)
                    .lineLimit(1...6)
                    .padding(DuetSpacing.tight)
                    .background(DuetColor.contentBackground)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(DuetColor.separator))
                    .focused($isFocused)
                    .disabled(!store.connectionState.isConnected || isSending)
                    .accessibilityLabel(L10n.interruptMessageAccessibility(language))
                    // ⌘Return sends; plain Return inserts a newline, which is
                    // what a multi-line instruction field should do.
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        send()
                        return .handled
                    }

                Button(action: send) {
                    Text(isSending ? L10n.sending(language) : L10n.interrupt(language))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSend)
                .accessibilityLabel(L10n.sendInterruptAccessibility(language))
            }
            .padding(.horizontal, DuetSpacing.loose)
            .padding(.bottom, DuetSpacing.regular)
        }
        .background(DuetColor.windowBackground)
    }

    private func send() {
        guard canSend else { return }
        let outgoingMessage = trimmedMessage
        isSending = true
        Task {
            let sent = await store.inject(message: outgoingMessage, to: recipient)
            if sent { message = "" }
            isSending = false
            isFocused = true
        }
    }
}
