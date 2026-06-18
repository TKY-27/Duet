import fs from "node:fs";
import path from "node:path";

/**
 * Best-effort current branch for a repoPath, read directly from Git metadata on disk
 * (no subprocess, no network). Returns the branch name, a short commit hash for a
 * detached HEAD, or "" on any error. Safe to call on every snapshot.
 */
export function readGitBranch(repoPath: string): string {
  try {
    const gitDir = resolveGitDir(path.join(repoPath, ".git"));
    if (!gitDir) return "";
    const head = fs.readFileSync(path.join(gitDir, "HEAD"), "utf8").trim();
    const refMatch = /^ref:\s*refs\/heads\/(.+)$/.exec(head);
    if (refMatch?.[1]) return refMatch[1];
    // Detached HEAD: the file holds a raw commit hash.
    return /^[0-9a-f]{7,40}$/i.test(head) ? head.slice(0, 7) : "";
  } catch {
    return "";
  }
}

function resolveGitDir(gitPath: string): string | undefined {
  const stats = fs.statSync(gitPath);
  if (stats.isDirectory()) return gitPath;
  if (stats.isFile()) {
    // Linked worktree or submodule: ".git" is a file "gitdir: <path>".
    const match = /^gitdir:\s*(.+)$/.exec(fs.readFileSync(gitPath, "utf8").trim());
    if (!match?.[1]) return undefined;
    return path.isAbsolute(match[1]) ? match[1] : path.resolve(path.dirname(gitPath), match[1]);
  }
  return undefined;
}
