import Foundation
import XCTest
@testable import Duet

final class DuetTests: XCTestCase {
    func testSnapshotDecodesNoProgressHoldSecFallback() throws {
        let payload = """
        {
          "running": true,
          "repoPath": "/tmp/duet-work",
          "roles": {
            "claude": { "role": "implementer", "task": "Implement." },
            "codex": { "role": "reviewer", "task": "Review." }
          },
          "transcript": [],
          "queues": { "claude": 0, "codex": 0 },
          "holdSec": 50,
          "progressIntervalSec": 20
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(Snapshot.self, from: payload)

        XCTAssertEqual(snapshot.noProgressHoldSec, 25)
        XCTAssertEqual(snapshot.stallThresholdSec, 120)
        XCTAssertEqual(snapshot.stalls.claude, .normal)
        // presence and repo were added after the first shipped Hub; an older
        // payload must still decode rather than failing the whole snapshot.
        XCTAssertEqual(snapshot.presence, .unseen)
        XCTAssertFalse(snapshot.repo.available)
    }

    func testSnapshotDecodesPresenceAndRepo() throws {
        let payload = """
        {
          "running": true,
          "repoPath": "/tmp/duet-work",
          "roles": {
            "claude": { "role": "implementer", "task": "Implement." },
            "codex": { "role": "reviewer", "task": "Review." }
          },
          "transcript": [],
          "queues": { "claude": 0, "codex": 0 },
          "holdSec": 50,
          "progressIntervalSec": 20,
          "presence": {
            "claude": { "connected": true, "everSeen": true, "sinceMs": 1200 },
            "codex": { "connected": false, "everSeen": true, "sinceMs": 95000 }
          },
          "repo": {
            "available": true,
            "branch": "feature/token-refresh",
            "head": "abc1234",
            "ahead": 2,
            "behind": 0,
            "truncated": false,
            "files": [
              { "path": "src/auth.ts", "status": "M", "added": 12, "removed": 3 }
            ]
          }
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(Snapshot.self, from: payload)

        XCTAssertTrue(snapshot.presence.claude.connected)
        XCTAssertFalse(snapshot.presence.codex.connected)
        XCTAssertEqual(snapshot.presence.codex.sinceSeconds, 95)
        XCTAssertEqual(snapshot.repo.branch, "feature/token-refresh")
        XCTAssertEqual(snapshot.repo.totalAdded, 12)
        XCTAssertEqual(snapshot.repo.totalRemoved, 3)
        XCTAssertEqual(snapshot.repo.files.first?.fileName, "auth.ts")
    }

    func testControlEventEnvelopeDecodesPresenceEvent() throws {
        let payload = #"{"type":"presence","agentId":"claude","connected":true,"everSeen":true,"sinceMs":800}"#
            .data(using: .utf8)!

        let event = try JSONDecoder().decode(ControlEventEnvelope.self, from: payload).event()

        XCTAssertEqual(
            event,
            .presence(agent: .claude, presence: AgentPresence(connected: true, everSeen: true, sinceMs: 800))
        )
    }

    func testControlEventEnvelopeDecodesRepoEvent() throws {
        let payload = """
        {"type":"repo","repo":{"available":true,"branch":"main","head":"deadbee",
        "ahead":0,"behind":1,"truncated":false,"files":[]}}
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(ControlEventEnvelope.self, from: payload).event()

        guard case .repo(let repo) = event else { return XCTFail("expected a repo event") }
        XCTAssertEqual(repo.branch, "main")
        XCTAssertEqual(repo.behind, 1)
    }

    func testControlEventEnvelopeRejectsUnknownEventAsUnsupported() throws {
        let payload = #"{"type":"somethingNewerHubsSend"}"#.data(using: .utf8)!
        let envelope = try JSONDecoder().decode(ControlEventEnvelope.self, from: payload)

        // Forward compatibility: an unmodelled event must be skippable, not a
        // decode failure that the client reports as an error every few seconds.
        XCTAssertThrowsError(try envelope.event()) { error in
            guard case ControlEventError.unsupported(let type) = error else {
                return XCTFail("expected ControlEventError.unsupported, got \(error)")
            }
            XCTAssertEqual(type, "somethingNewerHubsSend")
        }
    }

    func testControlEventEnvelopeDecodesErrorMessage() throws {
        let payload = #"{"type":"error","message":"Invalid control command."}"#.data(using: .utf8)!

        let event = try JSONDecoder().decode(ControlEventEnvelope.self, from: payload).event()

        XCTAssertEqual(event, .error("Invalid control command."))
    }

    func testControlEventEnvelopeDecodesStallEvent() throws {
        let payload = #"{"type":"stall","agentId":"codex","stalled":true,"sinceMs":121000}"#.data(using: .utf8)!

        let event = try JSONDecoder().decode(ControlEventEnvelope.self, from: payload).event()

        XCTAssertEqual(event, .stall(agent: .codex, stalled: true, sinceMs: 121_000))
    }

    func testBusMessageDisplaysHumanRecipient() throws {
        let payload = """
        {
          "seq": 7,
          "kind": "agent",
          "from": "claude",
          "to": "human",
          "message": "I paused before commit.",
          "createdAt": "2026-06-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(BusMessage.self, from: payload)

        XCTAssertEqual(message.recipientDisplayName(language: .japanese), "人間")
        XCTAssertEqual(message.recipientDisplayName(language: .english), "Human")
    }

    func testRoleValidatorRejectsInvalidRoleFields() {
        let roles = Roles(
            claude: RoleAssignment(role: "", task: "Implement."),
            codex: RoleAssignment(role: String(repeating: "r", count: RoleValidator.maxRoleLength + 1), task: "Review.")
        )

        let issues = RoleValidator.issues(for: roles)

        XCTAssertTrue(issues.contains { $0.agent == .claude && $0.field == .role })
        XCTAssertTrue(issues.contains { $0.agent == .codex && $0.field == .role })
    }

    func testErrorRedactorRemovesProjectRootHomeAndTokens() {
        let projectRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Projects/Duet")
        let raw = """
        \(projectRoot.path)/config/duet.config.json token=abc123 DUET_CONTROL_TOKEN=secret-value X-Duet-Control-Token: secret-value
        """

        let redacted = DuetErrorRedactor.redact(raw, projectRoot: projectRoot)

        XCTAssertFalse(redacted.contains(projectRoot.path))
        XCTAssertFalse(redacted.contains(FileManager.default.homeDirectoryForCurrentUser.path))
        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertFalse(redacted.contains("secret-value"))
    }
}
