import SwiftUI

struct InjectView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.duetPalette) private var palette
    @Environment(\.appLanguage) private var language
    @State private var recipient: Recipient = .both
    @State private var message = ""
    @State private var isSending = false

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedMessage.isEmpty && store.connectionState.isConnected && !isSending
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(L10n.interruptTarget(language))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.tertiaryText)

            Picker(L10n.recipient(language), selection: $recipient) {
                ForEach(Recipient.allCases) { recipient in
                    Text(recipient.displayName(language: language)).tag(recipient)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)

            TextField(L10n.interruptPlaceholder(language), text: $message)
                .textFieldStyle(DuetTextFieldStyle())
                .onSubmit(send)
                .disabled(!store.connectionState.isConnected || isSending)
                .accessibilityLabel(L10n.interruptMessageAccessibility(language))

            Button(action: send) {
                Label(isSending ? L10n.sending(language) : L10n.interrupt(language), systemImage: "arrow.right")
            }
            .buttonStyle(PrimaryControlButtonStyle(tint: palette.human))
            .disabled(!canSend)
            .accessibilityLabel(L10n.sendInterruptAccessibility(language))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(palette.toolbar)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }

    private func send() {
        guard canSend else { return }
        let outgoingMessage = trimmedMessage
        isSending = true
        Task {
            let sent = await store.inject(message: outgoingMessage, to: recipient)
            if sent {
                message = ""
            }
            isSending = false
        }
    }
}
