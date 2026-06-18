import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import test from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
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
  controlToken: "test-control-token-000000000000000",
  allowNonLoopbackHost: false,
  allowUnsafeRepoPath: false,
  maxTranscriptMessages: 300,
  maxQueueMessages: 100,
  maxWaitersPerAgent: 20,
  maxTransports: 40,
  maxMcpPayloadBytes: 64 * 1024,
  maxControlPayloadBytes: 16 * 1024,
  maxControlConnections: 5,
  maxRequestsPerMinute: 600,
  idleTransportTtlSec: 600,
  secretsPath: "/tmp/duet/config/duet.secrets.json",
  projectRoot: "/tmp/duet",
};

test("MCP clients can exchange a one-rally review message", async () => {
  const state = new DuetState(config);
  const app = createDuetExpressApp(state, config);
  const httpServer = createServer(app);
  await new Promise<void>((resolve) => httpServer.listen(0, "127.0.0.1", resolve));

  const address = httpServer.address();
  assert.notEqual(address, null);
  assert.notEqual(typeof address, "string");
  const port = (address as AddressInfo).port;

  const claude = await connectClient(
    `http://127.0.0.1:${port}/claude/${config.mcpTokens.claude}`,
    "claude-test-client",
  );
  const codex = await connectClient(
    `http://127.0.0.1:${port}/codex/${config.mcpTokens.codex}`,
    "codex-test-client",
  );

  try {
    const briefing = await claude.client.callTool({ name: "get_briefing", arguments: {} });
    assert.equal((briefing.structuredContent as Record<string, unknown> | undefined)?.agentId, "claude");

    const sent = await claude.client.callTool({
      name: "send",
      arguments: { message: "Please review src/auth.ts from disk." },
    });
    assert.equal((sent.structuredContent as SendResult | undefined)?.status, "sent");

    const received = await codex.client.callTool({
      name: "await_reply",
      arguments: { holdSec: 1 },
    });
    const payload = received.structuredContent as AwaitMessage | undefined;
    assert.equal(payload?.status, "message");
    assert.equal(payload?.from, "claude");
    assert.equal(payload?.message, "Please review src/auth.ts from disk.");
  } finally {
    await claude.client.close();
    await codex.client.close();
    await new Promise<void>((resolve, reject) => {
      httpServer.close((error) => (error ? reject(error) : resolve()));
    });
  }
});

test("MCP send accepts to human without enqueueing peer await replies", async () => {
  const state = new DuetState(config);
  const app = createDuetExpressApp(state, config);
  const httpServer = createServer(app);
  await new Promise<void>((resolve) => httpServer.listen(0, "127.0.0.1", resolve));

  const address = httpServer.address();
  assert.notEqual(address, null);
  assert.notEqual(typeof address, "string");
  const port = (address as AddressInfo).port;

  const claude = await connectClient(
    `http://127.0.0.1:${port}/claude/${config.mcpTokens.claude}`,
    "claude-human-send-test-client",
  );
  const codex = await connectClient(
    `http://127.0.0.1:${port}/codex/${config.mcpTokens.codex}`,
    "codex-human-send-test-client",
  );

  try {
    const sent = await claude.client.callTool({
      name: "send",
      arguments: { message: "I paused before committing.", to: "human" },
    });
    assert.equal((sent.structuredContent as SendResult | undefined)?.status, "sent");

    const transcript = state.snapshot().transcript;
    assert.equal(transcript.length, 1);
    assert.equal(transcript[0]?.kind, "agent");
    assert.equal(transcript[0]?.from, "claude");
    assert.equal(transcript[0]?.to, "human");

    const received = await codex.client.callTool({
      name: "await_reply",
      arguments: { holdSec: 1 },
    });
    const payload = received.structuredContent as AwaitEmpty | undefined;
    assert.equal(payload?.status, "empty");
  } finally {
    await claude.client.close();
    await codex.client.close();
    await new Promise<void>((resolve, reject) => {
      httpServer.close((error) => (error ? reject(error) : resolve()));
    });
  }
});

test("await_reply without a progress token is capped to noProgressHoldSec", async () => {
  const state = new DuetState({ ...config, holdSec: 5, noProgressHoldSec: 1 });
  const app = createDuetExpressApp(state, { ...config, holdSec: 5, noProgressHoldSec: 1 });
  const httpServer = createServer(app);
  await new Promise<void>((resolve) => httpServer.listen(0, "127.0.0.1", resolve));

  const address = httpServer.address();
  assert.notEqual(address, null);
  assert.notEqual(typeof address, "string");
  const port = (address as AddressInfo).port;

  const codex = await connectClient(
    `http://127.0.0.1:${port}/codex/${config.mcpTokens.codex}`,
    "codex-timeout-test-client",
  );
  const startedAt = Date.now();

  try {
    const received = await codex.client.callTool({
      name: "await_reply",
      arguments: { holdSec: 5 },
    });
    const elapsedMs = Date.now() - startedAt;
    const payload = received.structuredContent as AwaitEmpty | undefined;
    assert.equal(payload?.status, "empty");
    assert.ok(elapsedMs < 3000, `await_reply took ${elapsedMs}ms; expected no-progress cap`);
  } finally {
    await codex.client.close();
    await new Promise<void>((resolve, reject) => {
      httpServer.close((error) => (error ? reject(error) : resolve()));
    });
  }
});

test("await_reply sends progress notifications when requested", async () => {
  const progressConfig = { ...config, holdSec: 2, noProgressHoldSec: 1, progressIntervalSec: 1 };
  const state = new DuetState(progressConfig);
  const app = createDuetExpressApp(state, progressConfig);
  const httpServer = createServer(app);
  await new Promise<void>((resolve) => httpServer.listen(0, "127.0.0.1", resolve));

  const address = httpServer.address();
  assert.notEqual(address, null);
  assert.notEqual(typeof address, "string");
  const port = (address as AddressInfo).port;
  const codex = await connectClient(
    `http://127.0.0.1:${port}/codex/${config.mcpTokens.codex}`,
    "codex-progress-test-client",
  );
  const progressValues: number[] = [];

  try {
    const received = await codex.client.callTool(
      {
        name: "await_reply",
        arguments: { holdSec: 2 },
      },
      undefined,
      {
        timeout: 5_000,
        resetTimeoutOnProgress: true,
        onprogress: (progress) => {
          progressValues.push(progress.progress);
        },
      },
    );
    const payload = received.structuredContent as AwaitEmpty | undefined;
    assert.equal(payload?.status, "empty");
    assert.ok(progressValues.length >= 1, "expected at least one progress notification");
  } finally {
    await codex.client.close();
    await new Promise<void>((resolve, reject) => {
      httpServer.close((error) => (error ? reject(error) : resolve()));
    });
  }
});

test("oversized and malformed JSON payloads return minimal errors", async () => {
  const state = new DuetState({ ...config, maxMcpPayloadBytes: 1024 });
  const app = createDuetExpressApp(state, { ...config, maxMcpPayloadBytes: 1024 });
  const httpServer = createServer(app);
  await new Promise<void>((resolve) => httpServer.listen(0, "127.0.0.1", resolve));

  const address = httpServer.address();
  assert.notEqual(address, null);
  assert.notEqual(typeof address, "string");
  const port = (address as AddressInfo).port;
  const url = `http://127.0.0.1:${port}/codex/${config.mcpTokens.codex}`;

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
    await new Promise<void>((resolve, reject) => {
      httpServer.close((error) => (error ? reject(error) : resolve()));
    });
  }
});

test("legacy MCP paths are rejected and health details require control token", async () => {
  const state = new DuetState(config);
  const app = createDuetExpressApp(state, config);
  const httpServer = createServer(app);
  await new Promise<void>((resolve) => httpServer.listen(0, "127.0.0.1", resolve));

  const address = httpServer.address();
  assert.notEqual(address, null);
  assert.notEqual(typeof address, "string");
  const port = (address as AddressInfo).port;

  try {
    const legacy = await fetch(`http://127.0.0.1:${port}/claude`, { method: "POST" });
    assert.equal(legacy.status, 401);

    const health = (await (await fetch(`http://127.0.0.1:${port}/health`)).json()) as Record<string, unknown>;
    assert.deepEqual(health, { ok: true, service: "duet-hub" });

    const deniedDetails = await fetch(`http://127.0.0.1:${port}/health/details`);
    assert.equal(deniedDetails.status, 401);

    const details = await fetch(`http://127.0.0.1:${port}/health/details`, {
      headers: { "X-Duet-Control-Token": config.controlToken },
    });
    assert.equal(details.status, 200);
    const detailsPayload = (await details.json()) as Record<string, unknown>;
    assert.equal(detailsPayload.service, "duet-hub");
    assert.equal(detailsPayload.running, true);

    const deniedSetup = await fetch(`http://127.0.0.1:${port}/setup`);
    assert.equal(deniedSetup.status, 401);

    const setup = await fetch(`http://127.0.0.1:${port}/setup`, {
      headers: { "X-Duet-Control-Token": config.controlToken },
    });
    assert.equal(setup.status, 200);
    const setupPayload = (await setup.json()) as Record<string, unknown>;
    assert.match(String(setupPayload.claudeCommand), /claude mcp add-json duet/);
    assert.match(String(setupPayload.codexCommand), /codex mcp add duet/);
    assert.ok(String(setupPayload.claudeCommand).includes(config.mcpTokens.claude));
    assert.ok(String(setupPayload.codexCommand).includes(config.mcpTokens.codex));
  } finally {
    await new Promise<void>((resolve, reject) => {
      httpServer.close((error) => (error ? reject(error) : resolve()));
    });
  }
});

test("MCP bare route accepts bearer token without putting token in path", async () => {
  const state = new DuetState(config);
  const app = createDuetExpressApp(state, config);
  const httpServer = createServer(app);
  await new Promise<void>((resolve) => httpServer.listen(0, "127.0.0.1", resolve));

  const address = httpServer.address();
  assert.notEqual(address, null);
  assert.notEqual(typeof address, "string");
  const port = (address as AddressInfo).port;

  const claude = new Client({ name: "claude-bearer-test-client", version: "0.1.0" });
  const transport = new StreamableHTTPClientTransport(new URL(`http://127.0.0.1:${port}/claude`), {
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
    await new Promise<void>((resolve, reject) => {
      httpServer.close((error) => (error ? reject(error) : resolve()));
    });
  }
});

test("rate limit rejects abusive clients", async () => {
  const limitedConfig = { ...config, maxRequestsPerMinute: 1, idleTransportTtlSec: 1 };
  const state = new DuetState(limitedConfig);
  const app = createDuetExpressApp(state, limitedConfig);
  const httpServer = createServer(app);
  await new Promise<void>((resolve) => httpServer.listen(0, "127.0.0.1", resolve));

  const address = httpServer.address();
  assert.notEqual(address, null);
  assert.notEqual(typeof address, "string");
  const port = (address as AddressInfo).port;

  try {
    const first = await fetch(`http://127.0.0.1:${port}/health`);
    assert.equal(first.status, 200);
    const second = await fetch(`http://127.0.0.1:${port}/health`);
    assert.equal(second.status, 429);
  } finally {
    await new Promise<void>((resolve, reject) => {
      httpServer.close((error) => (error ? reject(error) : resolve()));
    });
  }
});

test("rate limit buckets are isolated per route", async () => {
  const limitedConfig = { ...config, maxRequestsPerMinute: 1, idleTransportTtlSec: 1 };
  const state = new DuetState(limitedConfig);
  const app = createDuetExpressApp(state, limitedConfig);
  const httpServer = createServer(app);
  await new Promise<void>((resolve) => httpServer.listen(0, "127.0.0.1", resolve));

  const address = httpServer.address();
  const port = (address as AddressInfo).port;

  try {
    // Exhaust the "health" bucket.
    assert.equal((await fetch(`http://127.0.0.1:${port}/health`)).status, 200);
    assert.equal((await fetch(`http://127.0.0.1:${port}/health`)).status, 429);
    // A different route bucket ("claude") must still be served: 401 for the missing token,
    // not 429 from the health plane's exhausted budget.
    assert.equal((await fetch(`http://127.0.0.1:${port}/claude`, { method: "POST" })).status, 401);
  } finally {
    await new Promise<void>((resolve, reject) => {
      httpServer.close((error) => (error ? reject(error) : resolve()));
    });
  }
});

async function connectClient(url: string, name: string): Promise<{ client: Client; transport: StreamableHTTPClientTransport }> {
  const client = new Client({ name, version: "0.1.0" });
  const transport = new StreamableHTTPClientTransport(new URL(url));
  await client.connect(transport);
  return { client, transport };
}
