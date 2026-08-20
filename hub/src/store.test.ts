import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { SessionStore, isSafeSessionId } from "./store.js";
import type { BusMessage, Roles, SessionSummary } from "./types.js";

function requireSession(summary: SessionSummary | undefined): SessionSummary {
  assert.ok(summary, "expected the store to open a session");
  return summary;
}


const roles: Roles = {
  claude: { role: "implementer", task: "Implement safely." },
  codex: { role: "reviewer", task: "Review carefully." },
};

function message(seq: number, text: string, from: BusMessage["from"] = "claude"): BusMessage {
  return {
    seq,
    kind: from === "human" ? "human" : "agent",
    from,
    to: from === "claude" ? "codex" : "claude",
    message: text,
    createdAt: new Date(Date.UTC(2026, 0, 1, 0, 0, seq)).toISOString(),
  };
}

function withStore(run: (store: SessionStore, rootDir: string) => void): void {
  const rootDir = mkdtempSync(path.join(tmpdir(), "duet-store-"));
  try {
    run(new SessionStore({ rootDir }), rootDir);
  } finally {
    rmSync(rootDir, { recursive: true, force: true });
  }
}

test("a session round-trips through disk", () => {
  withStore((store) => {
    const summary = requireSession(store.startSession("/tmp/repo", roles));
    store.append(message(1, "Please review src/auth.ts."));
    store.append(message(2, "Findings: the catch swallows the error.", "codex"));
    store.closeSession();

    const restored = store.read(summary.id);
    assert.equal(restored.length, 2);
    assert.equal(restored[0]?.message, "Please review src/auth.ts.");
    assert.equal(restored[1]?.from, "codex");
  });
});

test("the index lists sessions newest first with a title and count", () => {
  withStore((store) => {
    const first = requireSession(store.startSession("/tmp/repo", roles, new Date("2026-01-01T00:00:00.000Z")));
    store.append(message(1, "First session work."));
    const second = requireSession(store.startSession("/tmp/repo", roles, new Date("2026-02-01T00:00:00.000Z")));
    store.append(message(1, "Second session work."));
    store.closeSession();

    const listed = store.list();
    assert.deepEqual(
      listed.map((session) => session.id),
      [second.id, first.id],
    );
    assert.equal(listed[0]?.title, "Second session work.");
    assert.equal(listed[0]?.messageCount, 1);
    assert.equal(listed[0]?.roles.claude, "implementer");
  });
});

test("session files and the index are owner-readable only", () => {
  withStore((store, rootDir) => {
    const summary = requireSession(store.startSession("/tmp/repo", roles));
    store.append(message(1, "Sensitive coordination note."));
    store.closeSession();

    const sessionMode = statSync(path.join(rootDir, "sessions", `${summary.id}.jsonl`)).mode & 0o777;
    const indexMode = statSync(path.join(rootDir, "sessions.json")).mode & 0o777;
    assert.equal(sessionMode & 0o077, 0, `session file mode ${sessionMode.toString(8)} is group/world readable`);
    assert.equal(indexMode & 0o077, 0, `index mode ${indexMode.toString(8)} is group/world readable`);
  });
});

test("a torn final line does not lose the rest of the session", () => {
  withStore((store, rootDir) => {
    const summary = requireSession(store.startSession("/tmp/repo", roles));
    store.append(message(1, "Complete line."));
    store.closeSession();

    const file = path.join(rootDir, "sessions", `${summary.id}.jsonl`);
    writeFileSync(file, `${readFileSync(file, "utf8")}{"seq":2,"kind":"ag`);

    const restored = store.read(summary.id);
    assert.equal(restored.length, 1);
    assert.equal(restored[0]?.message, "Complete line.");
  });
});

test("a corrupt index degrades to an empty list instead of throwing", () => {
  withStore((store, rootDir) => {
    store.startSession("/tmp/repo", roles);
    store.append(message(1, "Recorded."));
    store.closeSession();
    writeFileSync(path.join(rootDir, "sessions.json"), "{ not json");

    assert.deepEqual(store.list(), []);
  });
});

test("Markdown export includes the header and every message", () => {
  withStore((store) => {
    const summary = requireSession(store.startSession("/tmp/repo", roles));
    store.append(message(1, "Please review src/auth.ts."));
    store.append(message(2, "Looks good.", "codex"));
    store.closeSession();

    const markdown = store.exportMarkdown(summary.id);
    assert.match(markdown, /# Duet session/);
    assert.match(markdown, /Please review src\/auth\.ts\./);
    assert.match(markdown, /Looks good\./);
    assert.match(markdown, /### Codex → Claude/);
  });
});

test("session ids outside the minted UUID shape are rejected", () => {
  assert.equal(isSafeSessionId("6f1b3c9e-4d2a-4c5b-9f8e-1a2b3c4d5e6f"), true);
  assert.equal(isSafeSessionId("../../etc/passwd"), false);
  assert.equal(isSafeSessionId("not-a-uuid"), false);
  assert.equal(isSafeSessionId(""), false);
});

test("reading an unknown or unsafe session id returns nothing", () => {
  withStore((store) => {
    assert.deepEqual(store.read("../../etc/passwd"), []);
    assert.deepEqual(store.read("6f1b3c9e-4d2a-4c5b-9f8e-1a2b3c4d5e6f"), []);
  });
});

test("an unwritable data directory disables history without breaking the room", () => {
  // A file where the directory should be makes every write fail, standing in
  // for a locked-down home or a read-only volume.
  const rootDir = mkdtempSync(path.join(tmpdir(), "duet-store-blocked-"));
  try {
    writeFileSync(path.join(rootDir, "sessions"), "not a directory");
    const store = new SessionStore({ rootDir });

    const summary = store.startSession("/tmp/repo", roles);
    assert.equal(summary, undefined);
    assert.ok(store.unavailableReason(), "expected a captured reason");

    // Appends and reads stay safe no-ops rather than throwing into the bus.
    store.append(message(1, "Should not be recorded."));
    assert.deepEqual(store.list(), []);
    assert.equal(store.currentSession(), undefined);
  } finally {
    rmSync(rootDir, { recursive: true, force: true });
  }
});
