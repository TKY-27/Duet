import assert from "node:assert/strict";
import { test } from "node:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { readGitBranch } from "./git.js";

function tmpRepo(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "duet-git-"));
}

test("readGitBranch reads a symbolic ref", () => {
  const dir = tmpRepo();
  fs.mkdirSync(path.join(dir, ".git"));
  fs.writeFileSync(path.join(dir, ".git", "HEAD"), "ref: refs/heads/feature/x\n");
  assert.equal(readGitBranch(dir), "feature/x");
});

test("readGitBranch shortens a detached HEAD to a short hash", () => {
  const dir = tmpRepo();
  fs.mkdirSync(path.join(dir, ".git"));
  fs.writeFileSync(path.join(dir, ".git", "HEAD"), "0123456789abcdef0123456789abcdef01234567\n");
  assert.equal(readGitBranch(dir), "0123456");
});

test("readGitBranch resolves a linked-worktree gitdir file", () => {
  const dir = tmpRepo();
  const realGit = path.join(dir, "realgit");
  fs.mkdirSync(realGit, { recursive: true });
  fs.writeFileSync(path.join(realGit, "HEAD"), "ref: refs/heads/main\n");
  fs.writeFileSync(path.join(dir, ".git"), `gitdir: ${realGit}\n`);
  assert.equal(readGitBranch(dir), "main");
});

test("readGitBranch returns empty string when git metadata is missing", () => {
  const dir = tmpRepo();
  assert.equal(readGitBranch(dir), "");
});
