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

    var glyph: String {
        switch self {
        case .claude: "C"
        case .codex: "</>"
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

enum DuetTheme: String, CaseIterable, Identifiable {
    case dark
    case light
    case terminal

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dark: "moon.fill"
        case .light: "sun.max.fill"
        case .terminal: "terminal.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .terminal: "Terminal"
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
        stalls: AgentStalls = .normal
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
    }

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
    }
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
    var sinceMs: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case snapshot
        case message
        case roles
        case running
        case agentId
        case stalled
        case sinceMs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        snapshot = try container.decodeIfPresent(Snapshot.self, forKey: .snapshot)
        roles = try container.decodeIfPresent(Roles.self, forKey: .roles)
        running = try container.decodeIfPresent(Bool.self, forKey: .running)
        agentId = try container.decodeIfPresent(AgentID.self, forKey: .agentId)
        stalled = try container.decodeIfPresent(Bool.self, forKey: .stalled)
        sinceMs = try container.decodeIfPresent(Int.self, forKey: .sinceMs)
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
        case "error":
            return .error(errorMessage ?? L10n.unknownHubError(.english))
        default:
            throw DecodingError.unknownEvent(type)
        }
    }
}

extension DecodingError {
    static func missingField(_ name: String) -> DecodingError {
        DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Missing field: \(name)"))
    }

    static func unknownEvent(_ type: String) -> DecodingError {
        DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown control event: \(type)"))
    }
}
