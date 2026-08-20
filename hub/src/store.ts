import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { randomUUID } from "node:crypto";
import type { BusMessage, Roles, SessionSummary } from "./types.js";

/**
 * Append-only session storage.
 *
 * Before this, the transcript lived only in memory: quitting Duet destroyed the
 * record of what the two agents agreed to do. Sessions are now JSONL files —
 * one JSON object per line — under the app support directory.
 *
 * JSONL rather than SQLite on purpose. The write pattern is append-only, a
 * session is a few hundred short messages, and a plain text file is readable
 * with `less`, greppable, diffable, trivially exportable, and needs no schema
 * migration or native module. `node:sqlite` is still a release candidate on
 * current Node and would be a disproportionate dependency for this shape of
 * data.
 */
const INDEX_FILE = "sessions.json";
const SESSIONS_DIR = "sessions";
const INDEX_VERSION = 1;
/** Title preview length; the first human-readable line of the session. */
const MAX_TITLE_LENGTH = 80;

interface SessionIndex {
  version: number;
  sessions: SessionSummary[];
}

export interface SessionStoreOptions {
  /** Root directory for session data. Defaults to the macOS app support path. */
  rootDir?: string;
}

export function defaultSessionRoot(): string {
  const override = process.env.DUET_DATA_DIR?.trim();
  if (override) return path.resolve(override);
  return path.join(os.homedir(), "Library", "Application Support", "Duet");
}

export class SessionStore {
  private readonly rootDir: string;
  private readonly sessionsDir: string;
  private readonly indexPath: string;
  private current: SessionSummary | undefined;
  private disabledReason: string | undefined;

  constructor(options: SessionStoreOptions = {}) {
    this.rootDir = options.rootDir ?? defaultSessionRoot();
    this.sessionsDir = path.join(this.rootDir, SESSIONS_DIR);
    this.indexPath = path.join(this.rootDir, INDEX_FILE);
  }

  /**
   * Opens a new session file and records it in the index.
   *
   * Recording history is a convenience, not a precondition for coordinating
   * two agents. If the data directory is unwritable — a locked-down home, a
   * read-only volume, restrictive TCC — persistence turns itself off and the
   * Hub keeps running with an in-memory transcript.
   */
  startSession(repoPath: string, roles: Roles, startedAt = new Date()): SessionSummary | undefined {
    this.closeSession();
    if (this.disabledReason) return undefined;

    const summary: SessionSummary = {
      id: randomUUID(),
      startedAt: startedAt.toISOString(),
      repoPath,
      title: "",
      messageCount: 0,
      roles: { claude: roles.claude.role, codex: roles.codex.role },
    };

    try {
      fs.mkdirSync(this.sessionsDir, { recursive: true, mode: 0o700 });
      // Written 0600: a transcript records what the human told the agents to do.
      fs.writeFileSync(this.sessionFile(summary.id), "", { flag: "a", mode: 0o600 });
      this.current = summary;
      this.writeIndexEntry(summary);
      return summary;
    } catch (error) {
      this.disable(error);
      return undefined;
    }
  }

  /** Non-undefined when persistence turned itself off, for GUI display. */
  unavailableReason(): string | undefined {
    return this.disabledReason;
  }

  private disable(error: unknown): void {
    this.current = undefined;
    this.disabledReason = error instanceof Error ? error.message : String(error);
    console.warn(`Duet session history is disabled: ${this.disabledReason}`);
  }

  currentSession(): SessionSummary | undefined {
    return this.current ? { ...this.current } : undefined;
  }

  /**
   * Appends one message to the open session. No-op when no session is open.
   *
   * Written synchronously: coordination messages arrive at human speed, so the
   * cost is irrelevant, and a buffered stream would lose the last messages when
   * Duet.app terminates the Hub — exactly the moment the record matters most.
   */
  append(message: BusMessage): void {
    if (!this.current) return;
    try {
      fs.appendFileSync(this.sessionFile(this.current.id), `${JSON.stringify(message)}\n`, { mode: 0o600 });
      this.current.messageCount += 1;
      if (!this.current.title) {
        this.current.title = summarize(message.message);
      }
      this.current.endedAt = message.createdAt;
      this.writeIndexEntry(this.current);
    } catch (error) {
      // A disk that fills or a directory that disappears mid-run must not stop
      // the two agents from talking to each other.
      this.disable(error);
    }
  }

  closeSession(): void {
    this.current = undefined;
  }

  /** Newest first. Returns an empty list when nothing has been recorded yet. */
  list(): SessionSummary[] {
    const index = this.readIndex();
    return [...index.sessions].sort((a, b) => b.startedAt.localeCompare(a.startedAt));
  }

  /** Reads a stored session's messages. Malformed lines are skipped, not fatal. */
  read(sessionId: string): BusMessage[] {
    if (!isSafeSessionId(sessionId)) return [];
    const file = this.sessionFile(sessionId);
    if (!fs.existsSync(file)) return [];
    const messages: BusMessage[] = [];
    for (const line of fs.readFileSync(file, "utf8").split("\n")) {
      if (!line.trim()) continue;
      try {
        messages.push(JSON.parse(line) as BusMessage);
      } catch {
        // A torn final line from an unclean shutdown must not lose the session.
      }
    }
    return messages;
  }

  /** Renders a session as Markdown for sharing or archiving. */
  exportMarkdown(sessionId: string): string {
    const summary = this.list().find((session) => session.id === sessionId);
    const messages = this.read(sessionId);
    const header = [
      `# Duet session ${sessionId}`,
      "",
      `- Started: ${summary?.startedAt ?? "unknown"}`,
      `- Repository: ${summary?.repoPath ?? "unknown"}`,
      `- Messages: ${messages.length}`,
      "",
      "---",
      "",
    ].join("\n");

    const body = messages
      .map((message) => {
        const who = message.from === "human" ? "Human" : capitalize(message.from);
        const to = message.to === "human" ? "human" : capitalize(String(message.to));
        return `### ${who} → ${to}\n\n*${message.createdAt}*\n\n${message.message}\n`;
      })
      .join("\n");

    return `${header}${body}`;
  }

  private sessionFile(sessionId: string): string {
    return path.join(this.sessionsDir, `${sessionId}.jsonl`);
  }

  private readIndex(): SessionIndex {
    if (!fs.existsSync(this.indexPath)) return { version: INDEX_VERSION, sessions: [] };
    try {
      const parsed = JSON.parse(fs.readFileSync(this.indexPath, "utf8")) as SessionIndex;
      if (!Array.isArray(parsed.sessions)) return { version: INDEX_VERSION, sessions: [] };
      return parsed;
    } catch {
      // A corrupt index must not prevent Duet from starting or recording new
      // sessions; the JSONL files remain on disk regardless.
      return { version: INDEX_VERSION, sessions: [] };
    }
  }

  private writeIndexEntry(summary: SessionSummary): void {
    const index = this.readIndex();
    const existing = index.sessions.findIndex((session) => session.id === summary.id);
    if (existing >= 0) {
      index.sessions[existing] = { ...summary };
    } else {
      index.sessions.push({ ...summary });
    }
    fs.mkdirSync(this.rootDir, { recursive: true, mode: 0o700 });
    const tempPath = `${this.indexPath}.tmp`;
    fs.writeFileSync(tempPath, `${JSON.stringify({ version: INDEX_VERSION, sessions: index.sessions }, null, 2)}\n`, {
      mode: 0o600,
    });
    // Rename so a crash mid-write cannot leave a truncated index behind.
    fs.renameSync(tempPath, this.indexPath);
  }
}

function summarize(message: string): string {
  const firstLine = message.split("\n").find((line) => line.trim().length > 0)?.trim() ?? "";
  return firstLine.length > MAX_TITLE_LENGTH ? `${firstLine.slice(0, MAX_TITLE_LENGTH - 1)}…` : firstLine;
}

function capitalize(value: string): string {
  return value.charAt(0).toUpperCase() + value.slice(1);
}

/** Session ids are server-minted UUIDs; reject anything that could escape the directory. */
export function isSafeSessionId(sessionId: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(sessionId);
}
