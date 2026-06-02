import SwiftUI

struct RoomView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.duetPalette) private var palette

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    if store.transcript.isEmpty {
                        EmptyLogView()
                    } else {
                        ForEach(store.transcript) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.vertical, 22)
                .padding(.horizontal, 54)
            }
            .textSelection(.enabled)
            .background(palette.log)
            .onChange(of: store.transcript.count) { _, _ in
                if let id = store.transcript.last?.id {
                    withAnimation(.easeOut(duration: 0.24)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct EmptyLogView: View {
    @Environment(\.duetPalette) private var palette
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 34))
                .foregroundStyle(palette.tertiaryText)
            Text(L10n.emptyLog(language))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
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
                Text(message.message)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .foregroundStyle(palette.text)
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

            Text(message.message)
                .font(.system(size: 14))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.text)

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
