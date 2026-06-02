import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { loadConfig } from "./config.js";

test("relative repoPath resolves from projectRoot, not process cwd", () => {
  const projectRoot = makeProjectRoot({
    repoPath: "workspace",
    roles: {
      claude: { role: "implementer", task: "Implement safely." },
      codex: { role: "reviewer", task: "Review carefully." },
    },
  });
  const previousRoot = process.env.DUET_REPO_ROOT;
  const previousToken = process.env.DUET_CONTROL_TOKEN;
  process.env.DUET_REPO_ROOT = projectRoot;
  process.env.DUET_CONTROL_TOKEN = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFG";

  try {
    const config = loadConfig(["--config", path.join(projectRoot, "config", "duet.config.json")]);
    assert.equal(config.projectRoot, projectRoot);
    assert.equal(config.repoPath, fs.realpathSync(path.join(projectRoot, "workspace")));
    assert.equal(config.controlToken, "0123456789abcdefghijklmnopqrstuvwxyzABCDEFG");
    assert.match(config.mcpTokens.claude, /^[A-Za-z0-9_-]{43,}$/);
    assert.match(config.mcpTokens.codex, /^[A-Za-z0-9_-]{43,}$/);
    assert.equal(config.secretsPath, path.join(projectRoot, "config", "duet.secrets.json"));
  } finally {
    restoreEnv("DUET_REPO_ROOT", previousRoot);
    restoreEnv("DUET_CONTROL_TOKEN", previousToken);
  }
});

test("non-loopback host requires explicit opt-in", () => {
  const projectRoot = makeProjectRoot({ host: "0.0.0.0", repoPath: "." });
  const previousRoot = process.env.DUET_REPO_ROOT;
  process.env.DUET_REPO_ROOT = projectRoot;

  try {
    assert.throws(
      () => loadConfig(["--config", path.join(projectRoot, "config", "duet.config.json")]),
      /Refusing non-loopback host/,
    );
  } finally {
    restoreEnv("DUET_REPO_ROOT", previousRoot);
  }
});

test("weak explicit control tokens are rejected", () => {
  const projectRoot = makeProjectRoot({ repoPath: "workspace" });
  const previousRoot = process.env.DUET_REPO_ROOT;
  const previousToken = process.env.DUET_CONTROL_TOKEN;
  process.env.DUET_REPO_ROOT = projectRoot;
  process.env.DUET_CONTROL_TOKEN = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

  try {
    assert.throws(
      () => loadConfig(["--config", path.join(projectRoot, "config", "duet.config.json")]),
      /low-entropy/,
    );
  } finally {
    restoreEnv("DUET_REPO_ROOT", previousRoot);
    restoreEnv("DUET_CONTROL_TOKEN", previousToken);
  }
});

test("unsafe repoPath values require explicit opt-in", () => {
  const projectRoot = makeProjectRoot({ repoPath: "." });
  const previousRoot = process.env.DUET_REPO_ROOT;
  process.env.DUET_REPO_ROOT = projectRoot;

  try {
    assert.throws(
      () => loadConfig(["--config", path.join(projectRoot, "config", "duet.config.json")]),
      /Refusing unsafe repoPath/,
    );
  } finally {
    restoreEnv("DUET_REPO_ROOT", previousRoot);
  }
});

test("repoPath must be a git worktree unless unsafe opt-in is enabled", () => {
  const projectRoot = makeProjectRoot({ repoPath: "workspace" });
  fs.rmSync(path.join(projectRoot, "workspace", ".git"), { recursive: true, force: true });
  const previousRoot = process.env.DUET_REPO_ROOT;
  process.env.DUET_REPO_ROOT = projectRoot;

  try {
    assert.throws(
      () => loadConfig(["--config", path.join(projectRoot, "config", "duet.config.json")]),
      /repoPath must point to a Git worktree/,
    );
  } finally {
    restoreEnv("DUET_REPO_ROOT", previousRoot);
  }
});

test("sensitive home repoPath values require unsafe opt-in even when git exists", () => {
  const projectRoot = makeProjectRoot({ repoPath: "workspace" });
  const fakeHome = fs.mkdtempSync(path.join(os.tmpdir(), "duet-home-test-"));
  const sensitivePath = path.join(fakeHome, ".ssh");
  fs.mkdirSync(path.join(sensitivePath, ".git"), { recursive: true });
  fs.writeFileSync(
    path.join(projectRoot, "config", "duet.config.json"),
    JSON.stringify({ repoPath: sensitivePath }),
  );
  const previousRoot = process.env.DUET_REPO_ROOT;
  const previousHome = process.env.HOME;
  process.env.DUET_REPO_ROOT = projectRoot;
  process.env.HOME = fakeHome;

  try {
    assert.throws(
      () => loadConfig(["--config", path.join(projectRoot, "config", "duet.config.json")]),
      /Refusing sensitive repoPath/,
    );
  } finally {
    restoreEnv("DUET_REPO_ROOT", previousRoot);
    restoreEnv("HOME", previousHome);
  }
});

test("role and task config rejects code and secret-like content", () => {
  const projectRoot = makeProjectRoot({
    repoPath: "workspace",
    roles: {
      claude: { role: "implementer", task: "api_key = sk-testsecret1234567890" },
      codex: { role: "reviewer", task: "Review carefully." },
    },
  });
  const previousRoot = process.env.DUET_REPO_ROOT;
  process.env.DUET_REPO_ROOT = projectRoot;

  try {
    assert.throws(
      () => loadConfig(["--config", path.join(projectRoot, "config", "duet.config.json")]),
      /secret/,
    );
  } finally {
    restoreEnv("DUET_REPO_ROOT", previousRoot);
  }
});

test("stallThresholdSec rejects values outside the observed range", () => {
  for (const stallThresholdSec of [29, 601]) {
    const projectRoot = makeProjectRoot({ repoPath: "workspace", stallThresholdSec });
    const previousRoot = process.env.DUET_REPO_ROOT;
    process.env.DUET_REPO_ROOT = projectRoot;

    try {
      assert.throws(
        () => loadConfig(["--config", path.join(projectRoot, "config", "duet.config.json")]),
        /stallThresholdSec/,
      );
    } finally {
      restoreEnv("DUET_REPO_ROOT", previousRoot);
    }
  }
});

test("existing secrets file must not be symlinked or group/world readable", () => {
  const projectRoot = makeProjectRoot({ repoPath: "workspace" });
  const configPath = path.join(projectRoot, "config", "duet.config.json");
  const secretsPath = path.join(projectRoot, "config", "duet.secrets.json");
  fs.writeFileSync(secretsPath, makeSecretsPayload());
  fs.chmodSync(secretsPath, 0o644);
  const previousRoot = process.env.DUET_REPO_ROOT;
  process.env.DUET_REPO_ROOT = projectRoot;

  try {
    assert.throws(() => loadConfig(["--config", configPath]), /group\/world-readable/);
    fs.rmSync(secretsPath);
    const targetPath = path.join(projectRoot, "config", "real-secrets.json");
    fs.writeFileSync(targetPath, makeSecretsPayload(), { mode: 0o600 });
    fs.symlinkSync(targetPath, secretsPath);
    assert.throws(() => loadConfig(["--config", configPath]), /symlinked secrets/);
  } finally {
    restoreEnv("DUET_REPO_ROOT", previousRoot);
  }
});

function makeProjectRoot(config: Record<string, unknown>): string {
  const projectRoot = fs.mkdtempSync(path.join(os.tmpdir(), "duet-config-test-"));
  fs.writeFileSync(path.join(projectRoot, "CLAUDE.md"), "# test\n");
  fs.mkdirSync(path.join(projectRoot, "config"));
  fs.mkdirSync(path.join(projectRoot, "workspace"));
  fs.mkdirSync(path.join(projectRoot, "workspace", ".git"));
  fs.writeFileSync(path.join(projectRoot, "config", "duet.config.json"), JSON.stringify(config));
  return projectRoot;
}

function restoreEnv(name: string, value: string | undefined): void {
  if (value === undefined) {
    delete process.env[name];
    return;
  }
  process.env[name] = value;
}

function makeSecretsPayload(): string {
  return JSON.stringify({
    version: 1,
    mcpTokens: {
      claude: "abcdefghijklmnopqrstuvwxyzABCDE_0123456789-abc",
      codex: "abcdefghijklmnopqrstuvwxyzABCDE_0123456789-def",
    },
  });
}
