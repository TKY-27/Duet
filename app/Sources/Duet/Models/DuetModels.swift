import Foundation
import SwiftUI

enum AgentID: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    var subtitle: String {
        switch self {
        case .claude: "anthropic · claude code"
        case .codex: "openai · codex"
        }
    }

    var accent: Color {
        switch self {
        case .claude: Color(red: 0.88, green: 0.54, blue: 0.17)
        case .codex: Color(red: 0.20, green: 0.71, blue: 0.84)
        }
    }

    var iconResourceName: String {
        switch self {
        case .claude: "claude-icon"
        case .codex: "codex-icon"
        }
    }
}

enum Recipient: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case both

    var id: String { rawValue }

    var displayName: String {
        displayName(language: .japanese)
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .claude:
            "Claude"
        case .codex:
            "Codex"
        case .both:
            switch language {
            case .japanese: "両方"
            case .english: "Both"
            }
        }
    }
}

struct RoleAssignment: Codable, Equatable {
    var role: String
    var task: String
}

enum RoleField: String, Equatable {
    case role
    case task
}

struct RoleValidationIssue: Identifiable, Equatable {
    var agent: AgentID
    var field: RoleField
    var message: String

    var id: String {
        "\(agent.rawValue)-\(field.rawValue)"
    }
}

enum RoleValidator {
    static let maxRoleLength = 120
    static let maxTaskLength = 4_000

    static func issues(for roles: Roles, language: AppLanguage = .japanese) -> [RoleValidationIssue] {
        AgentID.allCases.flatMap { agent in
            issues(for: agent, assignment: roles[agent], language: language)
        }
    }

    static func issue(for agent: AgentID, field: RoleField, in roles: Roles, language: AppLanguage = .japanese) -> RoleValidationIssue? {
        issues(for: agent, assignment: roles[agent], language: language).first { $0.field == field }
    }

    private static func issues(for agent: AgentID, assignment: RoleAssignment, language: AppLanguage) -> [RoleValidationIssue] {
        var issues: [RoleValidationIssue] = []
        let trimmedRole = assignment.role.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTask = assignment.task.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedRole.isEmpty {
            issues.append(RoleValidationIssue(agent: agent, field: .role, message: L10n.roleRequired(agent: agent.displayName, language: language)))
        }
        if trimmedRole.count > maxRoleLength {
            issues.append(
                RoleValidationIssue(
                    agent: agent,
                    field: .role,
                    message: L10n.roleTooLong(agent: agent.displayName, max: maxRoleLength, language: language)
                )
            )
        }
        if trimmedTask.count > maxTaskLength {
            issues.append(
                RoleValidationIssue(
                    agent: agent,
                    field: .task,
                    message: L10n.taskTooLong(agent: agent.displayName, max: maxTaskLength, language: language)
                )
            )
        }

        return issues
    }
}

struct Roles: Codable, Equatable {
    var claude: RoleAssignment
    var codex: RoleAssignment

    subscript(agent: AgentID) -> RoleAssignment {
        get {
            switch agent {
            case .claude: claude
            case .codex: codex
            }
        }
        set {
            switch agent {
            case .claude: claude = newValue
            case .codex: codex = newValue
            }
        }
    }
}

struct BusMessage: Codable, Identifiable, Equatable {
    var seq: Int
    var kind: String
    var from: String
    var to: String
    var message: String
    var createdAt: Date

    var id: Int { seq }

    var fromAgent: AgentID? { AgentID(rawValue: from) }
    var toRecipient: Recipient? { Recipient(rawValue: to) }

    func recipientDisplayName(language: AppLanguage) -> String {
        if to == "human" {
            switch language {
            case .japanese: return "人間"
            case .english: return "Human"
            }
        }
        return toRecipient?.displayName(language: language) ?? to
    }
}

struct Snapshot: Codable, Equatable {
    var running: Bool
    var repoPath: String
    var roles: Roles
    var transcript: [BusMessage]
    var queues: QueueDepth
    var holdSec: Int
    var noProgressHoldSec: Int
    var progressIntervalSec: Int
    var stallThresholdSec: Int
    var stalls: AgentStalls
    var presence: AgentPresences
    var repo: RepoStatus

    init(
        running: Bool,
        repoPath: String,
        roles: Roles,
        transcript: [BusMessage],
        queues: QueueDepth,
        holdSec: Int,
        noProgressHoldSec: Int,
        progressIntervalSec: Int,
        stallThresholdSec: Int = 120,
        stalls: AgentStalls = .normal,
        presence: AgentPresences = .unseen,
        repo: RepoStatus = .unavailable
    ) {
        self.running = running
        self.repoPath = repoPath
        self.roles = roles
        self.transcript = transcript
        self.queues = queues
        self.holdSec = holdSec
        self.noProgressHoldSec = noProgressHoldSec
        self.progressIntervalSec = progressIntervalSec
        self.stallThresholdSec = stallThresholdSec
        self.stalls = stalls
        self.presence = presence
        self.repo = repo
    }

    enum CodingKeys: String, CodingKey {
        case running
        case repoPath
        case roles
        case transcript
        case queues
        case holdSec
        case noProgressHoldSec
        case progressIntervalSec
        case stallThresholdSec
        case stalls
        case presence
        case repo
    }

    // Every optional field decodes through `decodeIfPresent ?? default` so that
    // adding a Hub field never breaks an older app, and so this initializer has
    // one uniform rule instead of a mix that has to be re-read on each change.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        running = try container.decode(Bool.self, forKey: .running)
        repoPath = try container.decode(String.self, forKey: .repoPath)
        roles = try container.decode(Roles.self, forKey: .roles)
        transcript = try container.decode([BusMessage].self, forKey: .transcript)
        queues = try container.decode(QueueDepth.self, forKey: .queues)
        holdSec = try container.decode(Int.self, forKey: .holdSec)
        noProgressHoldSec = try container.decodeIfPresent(Int.self, forKey: .noProgressHoldSec) ?? 25
        progressIntervalSec = try container.decode(Int.self, forKey: .progressIntervalSec)
        stallThresholdSec = try container.decodeIfPresent(Int.self, forKey: .stallThresholdSec) ?? 120
        stalls = try container.decodeIfPresent(AgentStalls.self, forKey: .stalls) ?? .normal
        presence = try container.decodeIfPresent(AgentPresences.self, forKey: .presence) ?? .unseen
        repo = try container.decodeIfPresent(RepoStatus.self, forKey: .repo) ?? .unavailable
    }
}

/// Whether an agent's MCP client has reached the Hub recently. Distinct from
/// `AgentStall`: presence answers "is it connected at all", stall answers
/// "connected but not making progress".
struct AgentPresence: Codable, Equatable {
    var connected: Bool
    var everSeen: Bool
    var sinceMs: Int

    var sinceSeconds: Int { max(0, sinceMs / 1_000) }

    static let unseen = AgentPresence(connected: false, everSeen: false, sinceMs: 0)
}

struct AgentPresences: Codable, Equatable {
    var claude: AgentPresence
    var codex: AgentPresence

    static let unseen = AgentPresences(claude: .unseen, codex: .unseen)

    subscript(agent: AgentID) -> AgentPresence {
        get {
            switch agent {
            case .claude: claude
            case .codex: codex
            }
        }
        set {
            switch agent {
            case .claude: claude = newValue
            case .codex: codex = newValue
            }
        }
    }
}

struct RepoFileChange: Codable, Equatable, Identifiable {
    var path: String
    /// Git short status code, or "untracked".
    var status: String
    var added: Int
    var removed: Int

    var id: String { path }

    var fileName: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

struct RepoStatus: Codable, Equatable {
    /// False when Git could not be read; the GUI shows the strip as unavailable.
    var available: Bool
    var branch: String
    var head: String
    var ahead: Int
    var behind: Int
    var files: [RepoFileChange]
    /// True when the change list was capped for transport.
    var truncated: Bool
    var error: String?

    static let unavailable = RepoStatus(
        available: false,
        branch: "",
        head: "",
        ahead: 0,
        behind: 0,
        files: [],
        truncated: false
    )

    var totalAdded: Int { files.reduce(0) { $0 + $1.added } }
    var totalRemoved: Int { files.reduce(0) { $0 + $1.removed } }
}

struct SessionSummary: Codable, Equatable, Identifiable {
    var id: String
    var startedAt: Date
    var endedAt: Date?
    var repoPath: String
    /// First human-readable line of the session, used as a list label.
    var title: String
    var messageCount: Int
    var roles: [String: String]

    var isActive: Bool { endedAt == nil }
}

struct QueueDepth: Codable, Equatable {
    var claude: Int
    var codex: Int
}

struct AgentStall: Codable, Equatable {
    var stalled: Bool
    var sinceMs: Int

    var sinceSeconds: Int {
        max(0, sinceMs / 1_000)
    }

    static let normal = AgentStall(stalled: false, sinceMs: 0)
}

struct AgentStalls: Codable, Equatable {
    var claude: AgentStall
    var codex: AgentStall

    static let normal = AgentStalls(claude: .normal, codex: .normal)

    subscript(agent: AgentID) -> AgentStall {
        get {
            switch agent {
            case .claude: claude
            case .codex: codex
            }
        }
        set {
            switch agent {
            case .claude: claude = newValue
            case .codex: codex = newValue
            }
        }
    }
}

enum ControlEvent: Equatable {
    case snapshot(Snapshot)
    case message(BusMessage)
    case rolesUpdated(Roles)
    case status(Bool)
    case stall(agent: AgentID, stalled: Bool, sinceMs: Int)
    case presence(agent: AgentID, presence: AgentPresence)
    case repo(RepoStatus)
    case sessions(summaries: [SessionSummary], currentSessionId: String?)
    case sessionTranscript(sessionId: String, transcript: [BusMessage])
    case error(String)
}

struct ControlEventEnvelope: Decodable {
    var type: String
    var snapshot: Snapshot?
    var message: BusMessage?
    var errorMessage: String?
    var roles: Roles?
    var running: Bool?
    var agentId: AgentID?
    var stalled: Bool?
    var connected: Bool?
    var everSeen: Bool?
    var sinceMs: Int?
    var repo: RepoStatus?
    var sessions: [SessionSummary]?
    var currentSessionId: String?
    var sessionId: String?
    var transcript: [BusMessage]?

    enum CodingKeys: String, CodingKey {
        case type
        case snapshot
        case message
        case roles
        case running
        case agentId
        case stalled
        case connected
        case everSeen
        case sinceMs
        case repo
        case sessions
        case currentSessionId
        case sessionId
        case transcript
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        snapshot = try container.decodeIfPresent(Snapshot.self, forKey: .snapshot)
        roles = try container.decodeIfPresent(Roles.self, forKey: .roles)
        running = try container.decodeIfPresent(Bool.self, forKey: .running)
        agentId = try container.decodeIfPresent(AgentID.self, forKey: .agentId)
        stalled = try container.decodeIfPresent(Bool.self, forKey: .stalled)
        connected = try container.decodeIfPresent(Bool.self, forKey: .connected)
        everSeen = try container.decodeIfPresent(Bool.self, forKey: .everSeen)
        sinceMs = try container.decodeIfPresent(Int.self, forKey: .sinceMs)
        repo = try container.decodeIfPresent(RepoStatus.self, forKey: .repo)
        sessions = try container.decodeIfPresent([SessionSummary].self, forKey: .sessions)
        currentSessionId = try container.decodeIfPresent(String.self, forKey: .currentSessionId)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        transcript = try container.decodeIfPresent([BusMessage].self, forKey: .transcript)
        if type == "error" {
            errorMessage = try container.decodeIfPresent(String.self, forKey: .message)
            message = nil
        } else {
            message = try container.decodeIfPresent(BusMessage.self, forKey: .message)
            errorMessage = nil
        }
    }
}

extension ControlEventEnvelope {
    func event() throws -> ControlEvent {
        switch type {
        case "snapshot":
            guard let snapshot else { throw DecodingError.missingField("snapshot") }
            return .snapshot(snapshot)
        case "message":
            guard let message else { throw DecodingError.missingField("message") }
            return .message(message)
        case "rolesUpdated":
            guard let roles else { throw DecodingError.missingField("roles") }
            return .rolesUpdated(roles)
        case "status":
            guard let running else { throw DecodingError.missingField("running") }
            return .status(running)
        case "stall":
            guard let agentId else { throw DecodingError.missingField("agentId") }
            guard let stalled else { throw DecodingError.missingField("stalled") }
            guard let sinceMs else { throw DecodingError.missingField("sinceMs") }
            return .stall(agent: agentId, stalled: stalled, sinceMs: sinceMs)
        case "presence":
            guard let agentId else { throw DecodingError.missingField("agentId") }
            guard let connected else { throw DecodingError.missingField("connected") }
            guard let sinceMs else { throw DecodingError.missingField("sinceMs") }
            return .presence(
                agent: agentId,
                presence: AgentPresence(connected: connected, everSeen: everSeen ?? connected, sinceMs: sinceMs)
            )
        case "repo":
            guard let repo else { throw DecodingError.missingField("repo") }
            return .repo(repo)
        case "sessions":
            guard let sessions else { throw DecodingError.missingField("sessions") }
            return .sessions(summaries: sessions, currentSessionId: currentSessionId)
        case "sessionTranscript":
            guard let sessionId else { throw DecodingError.missingField("sessionId") }
            guard let transcript else { throw DecodingError.missingField("transcript") }
            return .sessionTranscript(sessionId: sessionId, transcript: transcript)
        case "error":
            return .error(errorMessage ?? L10n.unknownHubError(.english))
        default:
            // A newer Hub may publish control events this build does not model
            // yet. Those are additive, so an older app must skip them quietly
            // rather than reporting an error for every one — they arrive
            // continuously.
            throw ControlEventError.unsupported(type)
        }
    }
}

enum ControlEventError: Error {
    case unsupported(String)
}

extension DecodingError {
    static func missingField(_ name: String) -> DecodingError {
        DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Missing field: \(name)"))
    }

}
