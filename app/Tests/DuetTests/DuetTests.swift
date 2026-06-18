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

    func testMarkdownExportRendersHeaderAndQuotedBody() {
        let message = BusMessage(seq: 3, kind: "agent", from: "claude", to: "codex", message: "Line one\nLine two", createdAt: Date(timeIntervalSince1970: 0))
        let roles = Roles(
            claude: RoleAssignment(role: "implementer", task: "x"),
            codex: RoleAssignment(role: "reviewer", task: "y")
        )

        let markdown = TranscriptExporter.markdown(
            transcript: [message],
            repoPath: "/tmp/repo",
            branch: "main",
            roles: roles,
            exportedAt: Date(timeIntervalSince1970: 0),
            language: .english
        )

        XCTAssertTrue(markdown.contains("# Duet transcript"))
        XCTAssertTrue(markdown.contains("/tmp/repo (main)"))
        XCTAssertTrue(markdown.contains("**Claude** (implementer) → Codex"))
        XCTAssertTrue(markdown.contains("> Line one"))
        XCTAssertTrue(markdown.contains("> Line two"))
    }

    func testJSONExportRoundTrips() throws {
        let message = BusMessage(seq: 1, kind: "human", from: "human", to: "both", message: "hi", createdAt: Date(timeIntervalSince1970: 0))

        let data = try TranscriptExporter.json(transcript: [message])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let roundTripped = try decoder.decode([BusMessage].self, from: data)

        XCTAssertEqual(roundTripped, [message])
    }

    func testPathLinkerRejectsOutsideRepoAndMissingFiles() throws {
        let fileManager = FileManager.default
        let repo = fileManager.temporaryDirectory.appendingPathComponent("duet-link-\(UUID().uuidString)")
        try fileManager.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: repo) }

        let file = repo.appendingPathComponent("src/foo.swift")
        try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "x".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertNotNil(PathLinker.resolvedFileURL("src/foo.swift", repoPath: repo.path), "in-repo existing file resolves")
        XCTAssertNotNil(PathLinker.resolvedFileURL("./src/foo.swift", repoPath: repo.path), "leading ./ resolves")
        XCTAssertNil(PathLinker.resolvedFileURL("src/missing.swift", repoPath: repo.path), "missing file is not linked")
        XCTAssertNil(PathLinker.resolvedFileURL("../../etc/passwd", repoPath: repo.path), "path traversal is rejected")
        XCTAssertNil(PathLinker.resolvedFileURL("/etc/hosts", repoPath: repo.path), "absolute path outside repo is rejected")
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
