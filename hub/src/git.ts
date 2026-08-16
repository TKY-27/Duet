import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { RepoStatus, RepoFileChange } from "./types.js";

const run = promisify(execFile);

/**
 * Read-only Git observation for the shared repository.
 *
 * Duet's whole premise is that the two agents edit real files on disk, so the
 * window should show what actually changed there rather than the placeholder
 * branch label the GUI used to display. This module answers that question and
 * nothing else:
 *
 * - every command is a fixed argument list; no value from config, the GUI, or
 *   an agent message is ever interpolated into a Git argument, so there is no
 *   argument-injection surface;
 * - only `repoPath` (already validated as a Git worktree at config load) is
 *   used, and only as the working directory;
 * - nothing here writes, stages, commits, checks out, or fetches.
 */
const GIT_TIMEOUT_MS = 5_000;
const GIT_MAX_BUFFER_BYTES = 4 * 1024 * 1024;
/** Bounds the payload pushed to the GUI when a run touches an unusual number of files. */
const MAX_REPORTED_FILES = 200;

export async function readRepoStatus(repoPath: string): Promise<RepoStatus> {
  try {
    const [branch, head, tracking, porcelain, numstat] = await Promise.all([
      git(repoPath, ["rev-parse", "--abbrev-ref", "HEAD"]),
      git(repoPath, ["rev-parse", "--short", "HEAD"]),
      trackingCounts(repoPath),
      git(repoPath, ["status", "--porcelain"]),
      git(repoPath, ["diff", "--numstat", "HEAD"]),
    ]);

    const files = mergeChanges(parsePorcelain(porcelain), parseNumstat(numstat));
    return {
      available: true,
      branch: branch === "HEAD" ? "detached" : branch,
      head,
      ahead: tracking.ahead,
      behind: tracking.behind,
      files: files.slice(0, MAX_REPORTED_FILES),
      truncated: files.length > MAX_REPORTED_FILES,
    };
  } catch (error) {
    // A missing binary, a repository lock, or a mid-rebase state must degrade
    // the status strip, never take the Hub down.
    return {
      available: false,
      branch: "unknown",
      head: "",
      ahead: 0,
      behind: 0,
      files: [],
      truncated: false,
      error: error instanceof Error ? error.message.split("\n")[0] : String(error),
    };
  }
}

async function git(repoPath: string, args: readonly string[]): Promise<string> {
  const { stdout } = await run("git", [...args], {
    cwd: repoPath,
    timeout: GIT_TIMEOUT_MS,
    maxBuffer: GIT_MAX_BUFFER_BYTES,
    windowsHide: true,
    // Keep Git non-interactive: never let it stop the Hub waiting on a prompt.
    env: { ...process.env, GIT_TERMINAL_PROMPT: "0", GIT_OPTIONAL_LOCKS: "0" },
  });
  return stdout.trim();
}

async function trackingCounts(repoPath: string): Promise<{ ahead: number; behind: number }> {
  try {
    // Fails when the branch has no upstream, which is normal for local work.
    const output = await git(repoPath, ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"]);
    const [behind = "0", ahead = "0"] = output.split(/\s+/);
    return { ahead: toCount(ahead), behind: toCount(behind) };
  } catch {
    return { ahead: 0, behind: 0 };
  }
}

function parsePorcelain(output: string): Map<string, RepoFileChange> {
  const files = new Map<string, RepoFileChange>();
  if (!output) return files;

  for (const line of output.split("\n")) {
    if (line.length < 4) continue;
    const code = line.slice(0, 2).trim();
    // Renames read as "old -> new"; report the destination, which is the file
    // a reviewer needs to open.
    const rawPath = line.slice(3);
    const path = rawPath.includes(" -> ") ? (rawPath.split(" -> ").at(-1) ?? rawPath) : rawPath;
    files.set(path, { path: unquote(path), status: code === "??" ? "untracked" : code, added: 0, removed: 0 });
  }
  return files;
}

function parseNumstat(output: string): Map<string, { added: number; removed: number }> {
  const counts = new Map<string, { added: number; removed: number }>();
  if (!output) return counts;

  for (const line of output.split("\n")) {
    const [added, removed, ...pathParts] = line.split("\t");
    const path = pathParts.join("\t");
    if (!path) continue;
    // "-" marks a binary file; report it as zero lines rather than NaN.
    counts.set(path, { added: toCount(added), removed: toCount(removed) });
  }
  return counts;
}

function mergeChanges(
  porcelain: Map<string, RepoFileChange>,
  numstat: Map<string, { added: number; removed: number }>,
): RepoFileChange[] {
  const merged = new Map(porcelain);
  for (const [path, counts] of numstat) {
    const existing = merged.get(path);
    if (existing) {
      existing.added = counts.added;
      existing.removed = counts.removed;
    } else {
      merged.set(path, { path: unquote(path), status: "M", ...counts });
    }
  }
  return [...merged.values()].sort((a, b) => a.path.localeCompare(b.path));
}

function toCount(value: string | undefined): number {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
}

/** Git quotes paths containing unusual bytes; show the readable form. */
function unquote(path: string): string {
  if (!path.startsWith('"') || !path.endsWith('"')) return path;
  try {
    return JSON.parse(path) as string;
  } catch {
    return path;
  }
}

export function repoStatusEquals(a: RepoStatus, b: RepoStatus): boolean {
  return (
    a.available === b.available &&
    a.branch === b.branch &&
    a.head === b.head &&
    a.ahead === b.ahead &&
    a.behind === b.behind &&
    a.truncated === b.truncated &&
    a.error === b.error &&
    a.files.length === b.files.length &&
    a.files.every((file, index) => {
      const other = b.files[index];
      return (
        other !== undefined &&
        file.path === other.path &&
        file.status === other.status &&
        file.added === other.added &&
        file.removed === other.removed
      );
    })
  );
}
