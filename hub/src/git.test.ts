import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { readRepoStatus, repoStatusEquals } from "./git.js";

function makeRepo(): string {
  const repoPath = mkdtempSync(path.join(tmpdir(), "duet-git-"));
  const run = (args: string[]): void => {
    execFileSync("git", args, { cwd: repoPath, stdio: "ignore" });
  };
  run(["init", "--initial-branch=main"]);
  run(["config", "user.email", "duet@example.invalid"]);
  run(["config", "user.name", "Duet Test"]);
  run(["config", "commit.gpgsign", "false"]);
  writeFileSync(path.join(repoPath, "auth.ts"), "export const a = 1;\n");
  run(["add", "."]);
  run(["commit", "-m", "initial"]);
  return repoPath;
}

test("readRepoStatus reports the branch and a clean tree", async () => {
  const repoPath = makeRepo();
  try {
    const status = await readRepoStatus(repoPath);
    assert.equal(status.available, true);
    assert.equal(status.branch, "main");
    assert.equal(status.files.length, 0);
    assert.equal(status.ahead, 0);
    assert.equal(status.behind, 0);
    assert.ok(status.head.length > 0, "expected a short HEAD sha");
  } finally {
    rmSync(repoPath, { recursive: true, force: true });
  }
});

test("readRepoStatus reports modified and untracked files with line counts", async () => {
  const repoPath = makeRepo();
  try {
    writeFileSync(path.join(repoPath, "auth.ts"), "export const a = 1;\nexport const b = 2;\n");
    writeFileSync(path.join(repoPath, "notes.md"), "scratch\n");

    const status = await readRepoStatus(repoPath);
    const byPath = new Map(status.files.map((file) => [file.path, file]));

    assert.equal(byPath.get("auth.ts")?.added, 1);
    assert.equal(byPath.get("auth.ts")?.removed, 0);
    assert.equal(byPath.get("notes.md")?.status, "untracked");
    assert.equal(status.truncated, false);
  } finally {
    rmSync(repoPath, { recursive: true, force: true });
  }
});

test("readRepoStatus degrades instead of throwing outside a repository", async () => {
  const notARepo = mkdtempSync(path.join(tmpdir(), "duet-not-git-"));
  try {
    const status = await readRepoStatus(notARepo);
    assert.equal(status.available, false);
    assert.equal(status.branch, "unknown");
    assert.equal(status.files.length, 0);
    assert.ok(status.error, "expected a captured error message");
  } finally {
    rmSync(notARepo, { recursive: true, force: true });
  }
});

test("readRepoStatus reports a detached HEAD without failing", async () => {
  const repoPath = makeRepo();
  try {
    const head = execFileSync("git", ["rev-parse", "HEAD"], { cwd: repoPath, encoding: "utf8" }).trim();
    execFileSync("git", ["checkout", "--detach", head], { cwd: repoPath, stdio: "ignore" });

    const status = await readRepoStatus(repoPath);
    assert.equal(status.available, true);
    assert.equal(status.branch, "detached");
  } finally {
    rmSync(repoPath, { recursive: true, force: true });
  }
});

test("readRepoStatus never runs Git outside the configured repoPath", async () => {
  // A nested directory that is not itself a repository must not silently
  // report its parent's state through Git's upward search.
  const repoPath = makeRepo();
  const outside = mkdtempSync(path.join(tmpdir(), "duet-outside-"));
  try {
    mkdirSync(path.join(outside, "nested"), { recursive: true });
    const status = await readRepoStatus(path.join(outside, "nested"));
    assert.equal(status.available, false);
  } finally {
    rmSync(repoPath, { recursive: true, force: true });
    rmSync(outside, { recursive: true, force: true });
  }
});

test("repoStatusEquals detects file-level changes so the GUI is not spammed", async () => {
  const repoPath = makeRepo();
  try {
    const first = await readRepoStatus(repoPath);
    const unchanged = await readRepoStatus(repoPath);
    assert.equal(repoStatusEquals(first, unchanged), true);

    writeFileSync(path.join(repoPath, "auth.ts"), "export const a = 2;\n");
    const changed = await readRepoStatus(repoPath);
    assert.equal(repoStatusEquals(first, changed), false);
  } finally {
    rmSync(repoPath, { recursive: true, force: true });
  }
});
