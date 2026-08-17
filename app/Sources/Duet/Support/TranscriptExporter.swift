import Foundation

/// Renders the in-memory transcript to a portable file. Pure and testable — the view layer
/// only handles the save panel and the actual write.
enum TranscriptExporter {
    enum Format: String, CaseIterable, Identifiable {
        case markdown
        case json

        var id: String { rawValue }

        var fileExtension: String {
            switch self {
            case .markdown: "md"
            case .json: "json"
            }
        }
    }

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func markdown(
        transcript: [BusMessage],
        repoPath: String,
        branch: String,
        roles: Roles,
        exportedAt: Date,
        language: AppLanguage
    ) -> String {
        var lines: [String] = []
        lines.append("# Duet transcript")
        lines.append("")
        if !repoPath.isEmpty {
            let branchSuffix = branch.isEmpty ? "" : " (\(branch))"
            lines.append("- Repository: \(repoPath)\(branchSuffix)")
        }
        lines.append("- Exported: \(timestamp.string(from: exportedAt))")
        lines.append("- Messages: \(transcript.count)")
        lines.append("")
        lines.append("---")
        lines.append("")

        for message in transcript {
            let sender = senderLabel(message)
            let roleSuffix = roleSuffix(for: message, roles: roles)
            let recipient = message.kind == "system" ? "" : " → \(message.recipientDisplayName(language: language))"
            lines.append("**\(sender)**\(roleSuffix)\(recipient) · \(timestamp.string(from: message.createdAt)) · #\(message.seq)")
            for bodyLine in message.message.split(separator: "\n", omittingEmptySubsequences: false) {
                lines.append("> \(bodyLine)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    static func json(transcript: [BusMessage]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(transcript)
    }

    private static func senderLabel(_ message: BusMessage) -> String {
        if let agent = message.fromAgent { return agent.displayName }
        if message.from == "human" { return "Human" }
        return "System"
    }

    private static func roleSuffix(for message: BusMessage, roles: Roles) -> String {
        guard let agent = message.fromAgent else { return "" }
        let role = roles[agent].role.trimmingCharacters(in: .whitespacesAndNewlines)
        return role.isEmpty ? "" : " (\(role))"
    }
}
