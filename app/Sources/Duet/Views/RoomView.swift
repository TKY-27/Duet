import SwiftUI

struct RoomView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.duetPalette) private var palette
    @Environment(\.appLanguage) private var language
    @AppStorage("duet.roomViewMode") private var roomViewMode: RoomViewMode = .chat
    @State private var isPinnedToBottom = true
    @State private var lastSeenSeq = 0
    @State private var didInitialScroll = false
    @State private var searchText = ""
    @State private var activeSenders: Set<String> = []

    private static let bottomAnchor = "duet.room.bottom"

    // Client-side filter over the in-memory transcript by free text and/or sender.
    private var displayedMessages: [BusMessage] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if activeSenders.isEmpty && query.isEmpty { return store.transcript }
        return store.transcript.filter { message in
            (activeSenders.isEmpty || activeSenders.contains(message.from))
                && (query.isEmpty || message.message.range(of: query, options: .caseInsensitive) != nil)
        }
    }

    private var unseenCount: Int {
        guard !isPinnedToBottom else { return 0 }
        return displayedMessages.reduce(into: 0) { total, message in
            if message.seq > lastSeenSeq { total += 1 }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !store.transcript.isEmpty {
                RoomSearchBar(text: $searchText, activeSenders: $activeSenders)
            }
            conversation
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: roomViewMode == .log ? 2 : 18) {
                    if store.transcript.isEmpty {
                        EmptyLogView()
                    } else if displayedMessages.isEmpty {
                        NoResultsView()
                    } else {
                        let messages = displayedMessages
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            if showsDaySeparator(in: messages, at: index) {
                                DaySeparator(date: message.createdAt)
                            }
                            row(for: message)
                                .id(message.id)
                        }
                        // Bottom sentinel: drives "pinned to bottom" tracking. As the
                        // user scrolls away from the newest message it leaves the lazy
                        // render window and onDisappear fires; scrolling back re-pins.
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchor)
                            .onAppear {
                                isPinnedToBottom = true
                                markLatestSeen()
                            }
                            .onDisappear { isPinnedToBottom = false }
                    }
                }
                .padding(.vertical, roomViewMode == .log ? 12 : 22)
                .padding(.horizontal, roomViewMode == .log ? 20 : 54)
            }
            .textSelection(.enabled)
            .background(palette.log)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == PathLinker.scheme else { return .systemAction }
                PathLinker.open(url, repoPath: store.repoPath)
                return .handled
            })
            // Observe the newest displayed message id (seq), not the count: once the
            // transcript reaches its cap the count stays fixed while messages still arrive.
            .onChange(of: displayedMessages.last?.id) { _, _ in
                guard isPinnedToBottom else { return }
                markLatestSeen()
                withAnimation(.easeOut(duration: 0.24)) {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
            .onAppear {
                guard !didInitialScroll, displayedMessages.last != nil else { return }
                didInitialScroll = true
                markLatestSeen()
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
            .overlay(alignment: .bottomTrailing) {
                if !isPinnedToBottom {
                    JumpToLatestButton(count: unseenCount) {
                        withAnimation(.easeOut(duration: 0.24)) {
                            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                        }
                    }
                    .padding(.trailing, 22)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: isPinnedToBottom)
        }
    }

    private func markLatestSeen() {
        if let seq = displayedMessages.last?.seq {
            lastSeenSeq = seq
        }
    }

    @ViewBuilder
    private func row(for message: BusMessage) -> some View {
        switch roomViewMode {
        case .chat: MessageRow(message: message)
        case .log: LogRow(message: message)
        }
    }

    private func showsDaySeparator(in messages: [BusMessage], at index: Int) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.current.isDate(messages[index - 1].createdAt, inSameDayAs: messages[index].createdAt)
    }
}

private struct JumpToLatestButton: View {
    @Environment(\.duetPalette) private var palette
    @Environment(\.appLanguage) private var language
    var count: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10.5, weight: .bold))
                Text(label)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(palette.elevated)
            .overlay(Capsule().stroke(palette.border, lineWidth: 1))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.18), radius: 7, y: 2)
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.text)
        .accessibilityLabel(L10n.jumpToLatest(language))
    }

    private var label: String {
        count > 0 ? L10n.jumpToLatestCount(language, count: count) : L10n.jumpToLatest(language)
    }
}

private struct RoomSearchBar: View {
    @Environment(\.duetPalette) private var palette
    @Environment(\.appLanguage) private var language
    @Binding var text: String
    @Binding var activeSenders: Set<String>

    private var chips: [(token: String, label: String, color: Color)] {
        [
            ("claude", AgentID.claude.displayName, AgentID.claude.accent),
            ("codex", AgentID.codex.displayName, AgentID.codex.accent),
            ("human", L10n.humanFilter(language), palette.human),
        ]
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.tertiaryText)
                TextField(L10n.searchPlaceholder(language), text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .accessibilityLabel(L10n.searchPlaceholder(language))
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.tertiaryText)
                    .accessibilityLabel(L10n.clearSearch(language))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(palette.input)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: 340)

            ForEach(chips, id: \.token) { chip in
                FilterChip(label: chip.label, color: chip.color, isOn: activeSenders.contains(chip.token)) {
                    if activeSenders.contains(chip.token) {
                        activeSenders.remove(chip.token)
                    } else {
                        activeSenders.insert(chip.token)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(palette.toolbar)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
    }
}

private struct FilterChip: View {
    @Environment(\.duetPalette) private var palette
    var label: String
    var color: Color
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : palette.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isOn ? color : palette.mono)
                .overlay(Capsule().stroke(isOn ? color : palette.border, lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct NoResultsView: View {
    @Environment(\.duetPalette) private var palette
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(palette.tertiaryText)
            Text(L10n.noResults(language))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

private struct DaySeparator: View {
    @Environment(\.duetPalette) private var palette
    var date: Date

    var body: some View {
        HStack(spacing: 10) {
            line
            Text(DuetFormatters.daySeparator.string(from: date))
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.tertiaryText)
                .fixedSize()
            line
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var line: some View {
        Rectangle().fill(palette.softBorder).frame(height: 1)
    }
}

private struct LogRow: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.duetPalette) private var palette
    @Environment(\.appLanguage) private var language
    var message: BusMessage

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(DuetFormatters.logTime.string(from: message.createdAt))
                .foregroundStyle(palette.tertiaryText)
            HStack(spacing: 0) {
                Text(source)
                    .foregroundStyle(sourceColor)
                    .fontWeight(.semibold)
                Text(arrow)
                    .foregroundStyle(palette.tertiaryText)
            }
            Text(PathLinker.attributedMessage(message.message, repoPath: store.repoPath))
                .foregroundStyle(palette.text)
                .tint(sourceColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12, design: .monospaced))
        .textSelection(.enabled)
        .help(tooltip)
    }

    private var source: String {
        message.fromAgent?.displayName.lowercased() ?? message.from
    }

    private var arrow: String {
        message.kind == "system" ? "" : " → \(message.recipientDisplayName(language: language))"
    }

    private var sourceColor: Color {
        if let agent = message.fromAgent { return agent.accent }
        if message.from == "human" { return palette.human }
        return palette.tertiaryText
    }

    private var tooltip: String {
        "#\(message.seq) · \(DuetFormatters.fullTimestamp.string(from: message.createdAt))"
    }
}

private struct EmptyLogView: View {
    @Environment(\.duetPalette) private var palette
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 30))
                    .foregroundStyle(palette.tertiaryText)
                Text(L10n.onboardingTitle(language))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.text)
                Text(L10n.emptyLog(language))
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.secondaryText)
            }

            VStack(alignment: .leading, spacing: 10) {
                OnboardingStep(number: 1, text: L10n.onboardingStep1(language))
                OnboardingStep(number: 2, text: L10n.onboardingStep2(language))
                OnboardingStep(number: 3, text: L10n.onboardingStep3(language))
                OnboardingStep(number: 4, text: L10n.onboardingStep4(language))
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 11))
                Text(L10n.onboardingHint(language))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(palette.tertiaryText)
        }
        .padding(26)
        .frame(maxWidth: 440, alignment: .leading)
        .background(palette.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.softBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, minHeight: 360)
    }
}

private struct OnboardingStep: View {
    @Environment(\.duetPalette) private var palette
    var number: Int
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.text)
                .frame(width: 20, height: 20)
                .background(palette.mono)
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct MessageRow: View {
    @Environment(\.duetPalette) private var palette
    var message: BusMessage

    var body: some View {
        Group {
            if message.kind == "human" || message.from == "human" {
                HumanMessage(message: message)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let agent = message.fromAgent {
                AgentMessage(message: message, agent: agent)
                    .frame(maxWidth: 680, alignment: agent == .claude ? .leading : .trailing)
                    .frame(maxWidth: .infinity, alignment: agent == .claude ? .leading : .trailing)
            } else {
                SystemMessage(message: message)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

private struct AgentMessage: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.duetPalette) private var palette
    @Environment(\.appLanguage) private var language
    var message: BusMessage
    var agent: AgentID

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if agent == .claude { AgentAvatar(agent: agent, size: 30) }
            VStack(alignment: agent == .claude ? .leading : .trailing, spacing: 4) {
                HStack(spacing: 7) {
                    if agent == .codex { Spacer(minLength: 0) }
                    Text(agent.displayName)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(agent.accent)
                    Text(store.roles[agent].role)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.tertiaryText)
                    if message.to == "human" {
                        Text("→ \(message.recipientDisplayName(language: language))")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(palette.human)
                    }
                    Text(DuetFormatters.messageTime.string(from: message.createdAt))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.tertiaryText)
                }
                Text(PathLinker.attributedMessage(message.message, repoPath: store.repoPath))
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .foregroundStyle(palette.text)
                    .tint(agent.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(agent.accent.opacity(0.13))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(agent.accent.opacity(0.32), lineWidth: 1)
                    )
                    .clipShape(MessageBubbleShape(agent: agent))
            }
            if agent == .codex { AgentAvatar(agent: agent, size: 30) }
        }
    }
}

private struct HumanMessage: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.duetPalette) private var palette
    @Environment(\.appLanguage) private var language
    var message: BusMessage

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(palette.human).frame(width: 6, height: 6)
                Text(L10n.humanLabel(language, recipient: recipientLabel))
            }
            .font(.system(size: 11, weight: .black))
            .tracking(0.4)
            .foregroundStyle(palette.human)

            Text(PathLinker.attributedMessage(message.message, repoPath: store.repoPath))
                .font(.system(size: 14))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.text)
                .tint(palette.human)

            Text(DuetFormatters.messageTime.string(from: message.createdAt))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(palette.tertiaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(palette.human.opacity(0.13))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.human.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: palette.human.opacity(0.10), radius: 0, x: 0, y: 0)
    }

    private var recipientLabel: String {
        message.recipientDisplayName(language: language)
    }
}

private struct SystemMessage: View {
    @Environment(\.duetPalette) private var palette
    var message: BusMessage

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(palette.tertiaryText).frame(width: 6, height: 6)
            Text(message.message)
            Text("·")
            Text(DuetFormatters.messageTime.string(from: message.createdAt))
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(palette.tertiaryText)
    }
}

private struct MessageBubbleShape: Shape {
    var agent: AgentID

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 14
        let corners: UIRectCornerCompat = agent == .claude
            ? [.topRight, .bottomLeft, .bottomRight]
            : [.topLeft, .bottomLeft, .bottomRight]
        return Path(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
    }
}

struct UIRectCornerCompat: OptionSet {
    let rawValue: Int
    static let topLeft = UIRectCornerCompat(rawValue: 1 << 0)
    static let topRight = UIRectCornerCompat(rawValue: 1 << 1)
    static let bottomLeft = UIRectCornerCompat(rawValue: 1 << 2)
    static let bottomRight = UIRectCornerCompat(rawValue: 1 << 3)
}

extension Path {
    init(roundedRect rect: CGRect, byRoundingCorners corners: UIRectCornerCompat, cornerRadii: CGSize) {
        var path = Path()
        let radius = min(cornerRadii.width, cornerRadii.height, min(rect.width, rect.height) / 2)
        let topLeft = corners.contains(.topLeft) ? radius : 0
        let topRight = corners.contains(.topRight) ? radius : 0
        let bottomLeft = corners.contains(.bottomLeft) ? radius : 0
        let bottomRight = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        if topRight > 0 {
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + topRight), control: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        if bottomRight > 0 {
            path.addQuadCurve(to: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        if bottomLeft > 0 {
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft), control: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        if topLeft > 0 {
            path.addQuadCurve(to: CGPoint(x: rect.minX + topLeft, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        }
        path.closeSubpath()
        self = path
    }
}
