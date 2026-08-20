import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import test from "node:test";
// Modern era (2026-07-28) client.
import { Client as ModernClient, StreamableHTTPClientTransport as ModernTransport } from "@modelcontextprotocol/client";
// Legacy (2025-era) client, kept as a devDependency on purpose: these tests are
// the evidence that the v2 Hub still serves the 2025 protocol that shipping
// versions of Claude Code and Codex.app may still speak.
import { Client as LegacyClient } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport as LegacyTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { createDuetExpressApp } from "./server.js";
import { DuetState } from "./state.js";
import type { AwaitEmpty, AwaitMessage, DuetConfig, SendResult } from "./types.js";

const config: DuetConfig = {
  host: "127.0.0.1",
  port: 0,
  repoPath: "/tmp/duet-mcp-test",
  roles: {
    claude: { role: "implementer", task: "Implement safely." },
    codex: { role: "reviewer", task: "Review carefully." },
  },
  mcpTokens: {
    claude: "claude-test-token-0123456789abcdefghijklmnopq",
    codex: "codex-test-token-0123456789abcdefghijklmnopqr",
  },
  holdSec: 1,
  noProgressHoldSec: 1,
  progressIntervalSec: 1,
  stallThresholdSec: 30,
  presenceTtlSec: 90,
  repoPollIntervalSec: 10,
  controlToken: "test-control-token-000000000000000",
  allowNonLoopbackHost: false,
  allowUnsafeRepoPath: false,
  allowUrlTokens: true,
  maxTranscriptMessages: 300,
  maxQueueMessages: 100,
  maxWaitersPerAgent: 20,
  maxMcpPayloadBytes: 64 * 1024,
  maxControlPayloadBytes: 16 * 1024,
  maxControlConnections: 5,
  maxRequestsPerMinute: 600,
  secretsPath: "/tmp/duet/config/duet.secrets.json",
  projectRoot: "/tmp/duet",
};

interface RunningHub {
  state: DuetState;
  port: number;
  baseUrl: string;
  stop: () => Promise<void>;
}

async function startHub(overrides: Partial<DuetConfig> = {}): Promise<RunningHub> {
  const hubConfig = { ...config, ...overrides };
  const state = new DuetState(hubConfig);
  const { app, close } = createDuetExpressApp(state, hubConfig);
  const httpServer = createServer(app);
  await new Promise<void>((resolve) => httpServer.listen(0, "127.0.0.1", resolve));

  const address = httpServer.address();
  assert.notEqual(address, null);
  assert.notEqual(typeof address, "string");
  const port = (address as AddressInfo).port;

  return {
    state,
    port,
    baseUrl: `http://127.0.0.1:${port}`,
    stop: async () => {
      await close();
      await closeServer(httpServer);
    },
  };
}

function closeServer(httpServer: Server): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    httpServer.close((error) => (error ? reject(error) : resolve()));
  });
}

/** Connects a 2025-era client, exactly as a pre-2026 MCP host would. */
async function connectLegacyClient(url: string, name: string): Promise<LegacyClient> {
  const client = new LegacyClient({ name, version: "0.1.0" });
  await client.connect(new LegacyTransport(new URL(url)));
  return client;
}

/**
 * Connects a 2026-07-28 client pinned to that revision, so a regression on the
 * modern path fails loudly instead of silently falling back to the legacy one.
 */
async function connectModernClient(url: string, name: string, token: string): Promise<ModernClient> {
  const client = new ModernClient(
    { name, version: "0.1.0" },
    { versionNegotiation: { mode: { pin: "2026-07-28" } } },
  );
  await client.connect(
    new ModernTransport(new URL(url), {
      requestInit: { headers: { Authorization: `Bearer ${token}` } },
    }),
  );
  return client;
}

test("legacy 2025-era MCP clients can exchange a one-rally review message", async () => {
  const hub = await startHub();
  const claude = await connectLegacyClient(`${hub.baseUrl}/claude/${config.mcpTokens.claude}`, "claude-test-client");
  const codex = await connectLegacyClient(`${hub.baseUrl}/codex/${config.mcpTokens.codex}`, "codex-test-client");

  try {
    const briefing = await claude.callTool({ name: "get_briefing", arguments: {} });
    assert.equal((briefing.structuredContent as Record<string, unknown> | undefined)?.agentId, "claude");

    const sent = await claude.callTool({
      name: "send",
      arguments: { message: "Please review src/auth.ts from disk." },
    });
    assert.equal((sent.structuredContent as SendResult | undefined)?.status, "sent");

    const received = await codex.callTool({ name: "await_reply", arguments: { holdSec: 1 } });
    const payload = received.structuredContent as AwaitMessage | undefined;
    assert.equal(payload?.status, "message");
    assert.equal(payload?.from, "claude");
    assert.equal(payload?.message, "Please review src/auth.ts from disk.");
  } finally {
    await claude.close();
    await codex.close();
    await hub.stop();
  }
});

test("modern 2026-07-28 MCP clients can exchange a one-rally review message", async () => {
  const hub = await startHub();
  const claude = await connectModernClient(`${hub.baseUrl}/claude`, "claude-modern-client", config.mcpTokens.claude);
  const codex = await connectModernClient(`${hub.baseUrl}/codex`, "codex-modern-client", config.mcpTokens.codex);

  try {
    const briefing = await claude.callTool({ name: "get_briefing", arguments: {} });
    assert.equal((briefing.structuredContent as Record<string, unknown> | undefined)?.agentId, "claude");

    const sent = await claude.callTool({
      name: "send",
      arguments: { message: "Please review src/auth.ts from disk." },
    });
    assert.equal((sent.structuredContent as SendResult | undefined)?.status, "sent");

    const received = await codex.callTool({ name: "await_reply", arguments: { holdSec: 1 } });
    const payload = received.structuredContent as AwaitMessage | undefined;
    assert.equal(payload?.status, "message");
    assert.equal(payload?.from, "claude");
  } finally {
    await claude.close();
    await codex.close();
    await hub.stop();
  }
});

test("both protocol eras share one bus: a modern sender reaches a legacy waiter", async () => {
  const hub = await startHub();
  const claude = await connectModernClient(`${hub.baseUrl}/claude`, "claude-crossera-modern", config.mcpTokens.claude);
  const codex = await connectLegacyClient(`${hub.baseUrl}/codex/${config.mcpTokens.codex}`, "codex-crossera-legacy");

  try {
    await claude.callTool({
      name: "send",
      arguments: { message: "Cross-era handoff: read src/auth.ts." },
    });

    const received = await codex.callTool({ name: "await_reply", arguments: { holdSec: 1 } });
    const payload = received.structuredContent as AwaitMessage | undefined;
    assert.equal(payload?.status, "message");
    assert.equal(payload?.from, "claude");
    assert.equal(payload?.message, "Cross-era handoff: read src/auth.ts.");
  } finally {
    await claude.close();
    await codex.close();
    await hub.stop();
  }
});

test("MCP send accepts to human without enqueueing peer await replies", async () => {
  const hub = await startHub();
  const claude = await connectLegacyClient(
    `${hub.baseUrl}/claude/${config.mcpTokens.claude}`,
    "claude-human-send-test-client",
  );
  const codex = await connectLegacyClient(
    `${hub.baseUrl}/codex/${config.mcpTokens.codex}`,
    "codex-human-send-test-client",
  );

  try {
    const sent = await claude.callTool({
      name: "send",
      arguments: { message: "I paused before committing.", to: "human" },
    });
    assert.equal((sent.structuredContent as SendResult | undefined)?.status, "sent");

    const transcript = hub.state.snapshot().transcript;
    assert.equal(transcript.length, 1);
    assert.equal(transcript[0]?.kind, "agent");
    assert.equal(transcript[0]?.from, "claude");
    assert.equal(transcript[0]?.to, "human");

    const received = await codex.callTool({ name: "await_reply", arguments: { holdSec: 1 } });
    assert.equal((received.structuredContent as AwaitEmpty | undefined)?.status, "empty");
  } finally {
    await claude.close();
    await codex.close();
    await hub.stop();
  }
});

test("await_reply without a progress token is capped to noProgressHoldSec", async () => {
  const hub = await startHub({ holdSec: 5, noProgressHoldSec: 1 });
  const codex = await connectLegacyClient(
    `${hub.baseUrl}/codex/${config.mcpTokens.codex}`,
    "codex-timeout-test-client",
  );
  const startedAt = Date.now();

  try {
    const received = await codex.callTool({ name: "await_reply", arguments: { holdSec: 5 } });
    const elapsedMs = Date.now() - startedAt;
    assert.equal((received.structuredContent as AwaitEmpty | undefined)?.status, "empty");
    assert.ok(elapsedMs < 3000, `await_reply took ${elapsedMs}ms; expected no-progress cap`);
  } finally {
    await codex.close();
    await hub.stop();
  }
});

test("await_reply sends progress notifications when requested", async () => {
  const hub = await startHub({ holdSec: 2, noProgressHoldSec: 1, progressIntervalSec: 1 });
  const codex = await connectLegacyClient(
    `${hub.baseUrl}/codex/${config.mcpTokens.codex}`,
    "codex-progress-test-client",
  );
  const progressValues: number[] = [];

  try {
    const received = await codex.callTool(
      { name: "await_reply", arguments: { holdSec: 2 } },
      undefined,
      {
        timeout: 5_000,
        resetTimeoutOnProgress: true,
        onprogress: (progress) => {
          progressValues.push(progress.progress);
        },
      },
    );
    assert.equal((received.structuredContent as AwaitEmpty | undefined)?.status, "empty");
    assert.ok(progressValues.length >= 1, "expected at least one progress notification");
  } finally {
    await codex.close();
    await hub.stop();
  }
});

test("await_reply streams progress to a modern client and is resolved by a live send", async () => {
  // Exercises the SSE path of nodeHttpBridge on the 2026-07-28 era: a progress
  // token upgrades the response to a stream, then a peer message arrives while
  // that stream is still open and must terminate it with the real result.
  const hub = await startHub({ holdSec: 6, noProgressHoldSec: 1, progressIntervalSec: 1 });
  const codex = await connectModernClient(`${hub.baseUrl}/codex`, "codex-modern-progress", config.mcpTokens.codex);
  const claude = await connectModernClient(`${hub.baseUrl}/claude`, "claude-modern-progress", config.mcpTokens.claude);
  const progressValues: number[] = [];

  try {
    const waiting = codex.callTool(
      { name: "await_reply", arguments: { holdSec: 6 } },
      {
        timeout: 15_000,
        resetTimeoutOnProgress: true,
        onprogress: (progress) => {
          progressValues.push(progress.progress);
        },
      },
    );

    // Let at least one keepalive flush through the stream before answering.
    await new Promise((resolve) => setTimeout(resolve, 1_500));
    await claude.callTool({ name: "send", arguments: { message: "Findings are on disk." } });

    const payload = (await waiting).structuredContent as AwaitMessage | undefined;
    assert.equal(payload?.status, "message");
    assert.equal(payload?.from, "claude");
    assert.equal(payload?.message, "Findings are on disk.");
    assert.ok(progressValues.length >= 1, "expected at least one streamed progress notification");
  } finally {
    await codex.close();
    await claude.close();
    await hub.stop();
  }
});

test("a progressToken of 0 still enables the full hold", async () => {
  // Regression: progress tokens are `string | number`, so 0 is a real token.
  // A truthiness check here collapses the hold to noProgressHoldSec and makes
  // agents fall out of the waiting loop far sooner than configured.
  const hub = await startHub({ holdSec: 3, noProgressHoldSec: 1 });
  const startedAt = Date.now();

  try {
    const response = await fetch(`${hub.baseUrl}/codex/${config.mcpTokens.codex}`, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json, text/event-stream" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: {
          name: "await_reply",
          arguments: { holdSec: 3 },
          _meta: { progressToken: 0 },
        },
      }),
    });
    await response.text();
    const elapsedMs = Date.now() - startedAt;
    assert.ok(elapsedMs >= 2500, `await_reply returned after ${elapsedMs}ms; expected the full 3s hold`);
  } finally {
    await hub.stop();
  }
});

test("oversized and malformed JSON payloads return minimal errors", async () => {
  const hub = await startHub({ maxMcpPayloadBytes: 1024 });
  const url = `${hub.baseUrl}/codex/${config.mcpTokens.codex}`;

  try {
    const malformed = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{not-json",
    });
    assert.equal(malformed.status, 400);
    assert.deepEqual(await malformed.json(), { ok: false, error: "Invalid JSON payload" });

    const oversized = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ payload: "x".repeat(2048) }),
    });
    assert.equal(oversized.status, 413);
    assert.deepEqual(await oversized.json(), { ok: false, error: "Payload too large" });
  } finally {
    await hub.stop();
  }
});

test("unauthenticated MCP requests are rejected and health details require control token", async () => {
  const hub = await startHub();

  try {
    const unauthenticated = await fetch(`${hub.baseUrl}/claude`, { method: "POST" });
    assert.equal(unauthenticated.status, 401);

    const health = (await (await fetch(`${hub.baseUrl}/health`)).json()) as Record<string, unknown>;
    assert.deepEqual(health, { ok: true, service: "duet-hub" });

    const deniedDetails = await fetch(`${hub.baseUrl}/health/details`);
    assert.equal(deniedDetails.status, 401);

    const details = await fetch(`${hub.baseUrl}/health/details`, {
      headers: { "X-Duet-Control-Token": config.controlToken },
    });
    assert.equal(details.status, 200);
    const detailsPayload = (await details.json()) as Record<string, unknown>;
    assert.equal(detailsPayload.service, "duet-hub");
    assert.equal(detailsPayload.running, true);
    assert.equal(detailsPayload.allowUrlTokens, true);

    const deniedSetup = await fetch(`${hub.baseUrl}/setup`);
    assert.equal(deniedSetup.status, 401);

    const setup = await fetch(`${hub.baseUrl}/setup`, {
      headers: { "X-Duet-Control-Token": config.controlToken },
    });
    assert.equal(setup.status, 200);
    const setupPayload = (await setup.json()) as Record<string, unknown>;
    assert.match(String(setupPayload.claudeCommand), /claude mcp add-json duet/);
    assert.match(String(setupPayload.codexCommand), /codex mcp add duet/);
    assert.ok(String(setupPayload.claudeCommand).includes(config.mcpTokens.claude));
    assert.ok(String(setupPayload.codexCommand).includes(config.mcpTokens.codex));
  } finally {
    await hub.stop();
  }
});

test("secret-bearing URL paths are rejected unless explicitly enabled", async () => {
  const hub = await startHub({ allowUrlTokens: false });

  try {
    const response = await fetch(`${hub.baseUrl}/claude/${config.mcpTokens.claude}`, { method: "POST" });
    assert.equal(response.status, 401);
    assert.match(await response.text(), /URL token fallback is disabled by default/);
  } finally {
    await hub.stop();
  }
});

test("a wrong per-agent token is rejected on the bare route", async () => {
  const hub = await startHub();

  try {
    const wrongToken = await fetch(`${hub.baseUrl}/claude`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        Authorization: `Bearer ${config.mcpTokens.codex}`,
      },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list" }),
    });
    assert.equal(wrongToken.status, 401);
  } finally {
    await hub.stop();
  }
});

test("MCP bare route accepts bearer token without putting token in path", async () => {
  const hub = await startHub();
  const claude = new LegacyClient({ name: "claude-bearer-test-client", version: "0.1.0" });
  const transport = new LegacyTransport(new URL(`${hub.baseUrl}/claude`), {
    requestInit: {
      headers: {
        Authorization: `Bearer ${config.mcpTokens.claude}`,
      },
    },
  });

  try {
    await claude.connect(transport);
    const briefing = await claude.callTool({ name: "get_briefing", arguments: {} });
    assert.equal((briefing.structuredContent as Record<string, unknown> | undefined)?.agentId, "claude");
  } finally {
    await claude.close();
    await hub.stop();
  }
});

test("rate limit rejects abusive clients", async () => {
  const hub = await startHub({ maxRequestsPerMinute: 1 });

  try {
    const first = await fetch(`${hub.baseUrl}/health`);
    assert.equal(first.status, 200);
    const second = await fetch(`${hub.baseUrl}/health`);
    assert.equal(second.status, 429);
  } finally {
    await hub.stop();
  }
});

test("rate limit buckets are isolated per route", async () => {
  const hub = await startHub({ maxRequestsPerMinute: 1 });

  try {
    // Exhaust the "health" bucket.
    assert.equal((await fetch(`${hub.baseUrl}/health`)).status, 200);
    assert.equal((await fetch(`${hub.baseUrl}/health`)).status, 429);
    // A different route bucket ("claude") must still be served: 401 for the
    // missing token, not 429 borrowed from the health plane's spent budget.
    assert.equal((await fetch(`${hub.baseUrl}/claude`, { method: "POST" })).status, 401);
  } finally {
    await hub.stop();
  }
});
