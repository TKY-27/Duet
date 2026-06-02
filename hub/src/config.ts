import fs from "node:fs";
import path from "node:path";
import { randomBytes } from "node:crypto";
import { fileURLToPath } from "node:url";
import * as z from "zod/v4";
import { assertSafeRoleAssignment } from "./contentSafety.js";
import type { AgentId, DuetConfig, RoleAssignment, Roles } from "./types.js";

const RoleAssignmentSchema = z
  .object({
    role: z.string().trim().min(1).max(120),
    task: z.string().trim().max(4000),
  })
  .strict();

const RawConfigSchema = z
  .object({
    host: z.string().trim().min(1).default("127.0.0.1"),
    port: z.number().int().min(1024).max(65535).default(8765),
    repoPath: z.string().trim().min(1).optional(),
    allowNonLoopbackHost: z.boolean().default(false),
    allowUnsafeRepoPath: z.boolean().default(false),
    roles: z
      .object({
        claude: RoleAssignmentSchema,
        codex: RoleAssignmentSchema,
      })
      .strict()
      .optional(),
    holdSec: z.number().int().min(1).max(300).default(50),
    noProgressHoldSec: z.number().int().min(1).max(60).default(25),
    progressIntervalSec: z.number().int().min(1).max(60).default(20),
    stallThresholdSec: z.number().int().min(30).max(600).default(120),
    maxTranscriptMessages: z.number().int().min(1).max(10000).default(300),
    maxQueueMessages: z.number().int().min(1).max(1000).default(100),
    maxWaitersPerAgent: z.number().int().min(1).max(100).default(20),
    maxTransports: z.number().int().min(1).max(200).default(40),
    maxMcpPayloadBytes: z.number().int().min(1024).max(1024 * 1024).default(64 * 1024),
    maxControlPayloadBytes: z.number().int().min(1024).max(1024 * 1024).default(16 * 1024),
    maxControlConnections: z.number().int().min(1).max(20).default(5),
    maxRequestsPerMinute: z.number().int().min(10).max(10000).default(600),
    idleTransportTtlSec: z.number().int().min(1).max(86400).default(600),
  })
  .strict();

type RawConfig = z.infer<typeof RawConfigSchema>;

const AgentSecretsSchema = z
  .object({
    version: z.literal(1).default(1),
    mcpTokens: z
      .object({
        claude: z.string().trim().min(43),
        codex: z.string().trim().min(43),
      })
      .strict(),
  })
  .strict();

type AgentSecrets = z.infer<typeof AgentSecretsSchema>;

const DEFAULT_ROLES: Roles = {
  claude: {
    role: "implementer",
    task: "Implement the requested change in the shared repository, then ask Codex for review.",
  },
  codex: {
    role: "reviewer",
    task: "Wait for Claude, read the changed files from disk, and review the implementation.",
  },
};

export function loadConfig(argv: readonly string[] = process.argv.slice(2)): DuetConfig {
  const projectRoot = discoverProjectRoot();
  const cliConfigPath = readFlagValue(argv, "--config");
  const explicitConfigPath = process.env.DUET_CONFIG ?? cliConfigPath;
  const configPath = resolveConfigPath(projectRoot, explicitConfigPath);
  const fileConfig = configPath ? readConfigFile(configPath) : {};
  const parsed = RawConfigSchema.parse(fileConfig);
  validateHost(parsed.host, parsed.allowNonLoopbackHost);
  const roles = normalizeRoles(parsed.roles);
  const repoPath = resolveRepoPath(projectRoot, parsed.repoPath, parsed.allowUnsafeRepoPath);
  const secretsPath = resolveSecretsPath(projectRoot);
  const secrets = readOrCreateAgentSecrets(secretsPath);
  return {
    host: parsed.host,
    port: readPortOverride(argv) ?? parsed.port,
    repoPath,
    roles,
    mcpTokens: secrets.mcpTokens,
    holdSec: parsed.holdSec,
    noProgressHoldSec: parsed.noProgressHoldSec,
    progressIntervalSec: parsed.progressIntervalSec,
    stallThresholdSec: parsed.stallThresholdSec,
    controlToken: readControlToken(),
    allowNonLoopbackHost: parsed.allowNonLoopbackHost,
    allowUnsafeRepoPath: parsed.allowUnsafeRepoPath,
    maxTranscriptMessages: parsed.maxTranscriptMessages,
    maxQueueMessages: parsed.maxQueueMessages,
    maxWaitersPerAgent: parsed.maxWaitersPerAgent,
    maxTransports: parsed.maxTransports,
    maxMcpPayloadBytes: parsed.maxMcpPayloadBytes,
    maxControlPayloadBytes: parsed.maxControlPayloadBytes,
    maxControlConnections: parsed.maxControlConnections,
    maxRequestsPerMinute: parsed.maxRequestsPerMinute,
    idleTransportTtlSec: parsed.idleTransportTtlSec,
    ...(configPath ? { configPath } : {}),
    secretsPath,
    projectRoot,
  };
}

function resolveRepoPath(projectRoot: string, repoPath: string | undefined, allowUnsafeRepoPath: boolean): string {
  if (!repoPath) {
    throw new Error("repoPath must be configured in config/duet.config.json.");
  }

  const resolved = path.isAbsolute(repoPath) ? path.resolve(repoPath) : path.resolve(projectRoot, repoPath);
  if (!fs.existsSync(resolved)) {
    throw new Error(`repoPath does not exist: ${resolved}`);
  }
  const stats = fs.statSync(resolved);
  if (!stats.isDirectory()) {
    throw new Error(`repoPath must be a directory: ${resolved}`);
  }

  const realRepoPath = fs.realpathSync(resolved);
  validateSafeRepoPath(projectRoot, realRepoPath, allowUnsafeRepoPath);
  return realRepoPath;
}

function normalizeRoles(roles: RawConfig["roles"]): Roles {
  const normalized = {
    claude: roles?.claude ? cloneRole(roles.claude) : cloneRole(DEFAULT_ROLES.claude),
    codex: roles?.codex ? cloneRole(roles.codex) : cloneRole(DEFAULT_ROLES.codex),
  };
  assertSafeRoleAssignment("Claude", normalized.claude);
  assertSafeRoleAssignment("Codex", normalized.codex);
  return normalized;
}

function cloneRole(role: RoleAssignment): RoleAssignment {
  return { role: role.role, task: role.task };
}

function readFlagValue(argv: readonly string[], name: string): string | undefined {
  const index = argv.indexOf(name);
  if (index < 0) return undefined;
  const value = argv[index + 1];
  return value && !value.startsWith("--") ? value : undefined;
}

function readPortOverride(argv: readonly string[]): number | undefined {
  const raw = readFlagValue(argv, "--port");
  if (!raw) return undefined;
  const port = Number(raw);
  if (!Number.isInteger(port) || port < 1024 || port > 65535) {
    throw new Error(`Invalid --port value: ${raw}`);
  }
  return port;
}

function resolveConfigPath(projectRoot: string, explicitPath: string | undefined): string | undefined {
  if (explicitPath) {
    const resolved = path.resolve(explicitPath);
    if (!fs.existsSync(resolved)) {
      throw new Error(`Config file not found: ${resolved}`);
    }
    return resolved;
  }

  const localConfig = path.join(projectRoot, "config", "duet.config.json");
  if (fs.existsSync(localConfig)) return localConfig;

  return undefined;
}

function readConfigFile(configPath: string): unknown {
  try {
    return JSON.parse(fs.readFileSync(configPath, "utf8"));
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`Could not read ${configPath}: ${message}`);
  }
}

function resolveSecretsPath(projectRoot: string): string {
  return path.join(projectRoot, "config", "duet.secrets.json");
}

function readOrCreateAgentSecrets(secretsPath: string): AgentSecrets {
  if (fs.existsSync(secretsPath)) {
    validateSecretsFile(secretsPath);
    const parsed = AgentSecretsSchema.parse(readConfigFile(secretsPath));
    validateGeneratedToken(parsed.mcpTokens.claude, "claude MCP token");
    validateGeneratedToken(parsed.mcpTokens.codex, "codex MCP token");
    return parsed;
  }

  fs.mkdirSync(path.dirname(secretsPath), { recursive: true });
  const secrets: AgentSecrets = {
    version: 1,
    mcpTokens: {
      claude: generateSecretToken(),
      codex: generateSecretToken(),
    },
  };
  fs.writeFileSync(secretsPath, `${JSON.stringify(secrets, null, 2)}\n`, { mode: 0o600 });
  return secrets;
}

function validateSecretsFile(secretsPath: string): void {
  const linkStats = fs.lstatSync(secretsPath);
  if (linkStats.isSymbolicLink()) {
    throw new Error(`Refusing symlinked secrets file: ${secretsPath}`);
  }

  const mode = fs.statSync(secretsPath).mode & 0o777;
  if ((mode & 0o077) !== 0) {
    throw new Error(`Refusing group/world-readable secrets file: ${secretsPath}. Run chmod 600 on this file.`);
  }
}

function discoverProjectRoot(): string {
  const envRoot = process.env.DUET_REPO_ROOT;
  if (envRoot) return path.resolve(envRoot);

  const candidates = [process.cwd(), path.dirname(fileURLToPath(import.meta.url))];
  for (const candidate of candidates) {
    const found = findUp(candidate, "CLAUDE.md");
    if (found) return found;
  }

  return path.resolve(process.cwd(), "..");
}

function readControlToken(): string {
  const token = process.env.DUET_CONTROL_TOKEN?.trim();
  if (!token) return generateSecretToken();
  validateGeneratedToken(token, "DUET_CONTROL_TOKEN");
  return token;
}

function generateSecretToken(): string {
  return randomBytes(32).toString("base64url");
}

function validateGeneratedToken(token: string, label: string): void {
  if (!/^[A-Za-z0-9_-]{43,}$/.test(token)) {
    throw new Error(`${label} must be at least 32 bytes of base64url entropy.`);
  }
  if (new Set(token).size < 16) {
    throw new Error(`${label} must not be a low-entropy repeated value.`);
  }
}

function validateSafeRepoPath(projectRoot: string, repoPath: string, allowUnsafeRepoPath: boolean): void {
  if (allowUnsafeRepoPath) return;

  const realProjectRoot = fs.realpathSync(projectRoot);
  const home = fs.realpathSync(process.env.HOME ?? path.parse(repoPath).root);
  const root = path.parse(repoPath).root;
  const forbiddenExact = new Set([root, home, realProjectRoot]);
  if (forbiddenExact.has(repoPath)) {
    throw new Error(`Refusing unsafe repoPath without allowUnsafeRepoPath: ${repoPath}`);
  }

  const forbiddenPrefixes = ["/System", "/Library", "/bin", "/sbin", "/usr", "/etc", "/var"];
  if (forbiddenPrefixes.some((prefix) => repoPath === prefix || repoPath.startsWith(`${prefix}/`))) {
    throw new Error(`Refusing system repoPath without allowUnsafeRepoPath: ${repoPath}`);
  }

  const sensitiveHomePrefixes = [".ssh", ".gnupg", ".aws", ".config", "Library"].map((name) =>
    path.join(home, name),
  );
  if (sensitiveHomePrefixes.some((prefix) => repoPath === prefix || repoPath.startsWith(`${prefix}/`))) {
    throw new Error(`Refusing sensitive repoPath without allowUnsafeRepoPath: ${repoPath}`);
  }

  if (!fs.existsSync(path.join(repoPath, ".git"))) {
    throw new Error(`repoPath must point to a Git worktree unless allowUnsafeRepoPath is enabled: ${repoPath}`);
  }
}

function validateHost(host: string, allowNonLoopbackHost: boolean): void {
  if (allowNonLoopbackHost || isLoopbackHost(host)) return;
  throw new Error(`Refusing non-loopback host without explicit opt-in: ${host}`);
}

function isLoopbackHost(host: string): boolean {
  const normalized = host.toLowerCase();
  return normalized === "127.0.0.1" || normalized === "localhost" || normalized === "::1" || normalized === "[::1]";
}

function findUp(start: string, marker: string): string | undefined {
  let current = path.resolve(start);
  while (true) {
    if (fs.existsSync(path.join(current, marker))) return current;
    const parent = path.dirname(current);
    if (parent === current) return undefined;
    current = parent;
  }
}

export function roleFor(config: DuetConfig, agentId: AgentId): RoleAssignment {
  return cloneRole(config.roles[agentId]);
}
