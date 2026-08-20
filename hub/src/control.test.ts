import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import test from "node:test";
import { WebSocket } from "ws";
import { attachControlServer } from "./control.js";
import { DuetState } from "./state.js";
import type { DuetConfig } from "./types.js";

const config: DuetConfig = {
  host: "127.0.0.1",
  port: 0,
  repoPath: "/tmp/duet-control-test",
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
  allowUrlTokens: false,
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

test("control WebSocket sends snapshot and injects human messages", async () => {
  const state = new DuetState(config);
  const httpServer = createServer();
  const controlServer = attachControlServer(httpServer, state, config);
  await new Promise<void>((resolve) => httpServer.listen(0, "127.0.0.1", resolve));

  const address = httpServer.address();
  assert.notEqual(address, null);
  assert.notEqual(typeof address, "string");
  const port = (address as AddressInfo).port;
  const socket = new WebSocket(`ws://127.0.0.1:${port}/control`, {
    headers: { "X-Duet-Control-Token": config.controlToken },
  });

  try {
    const snapshot = await nextJson(socket);
    assert.equal(snapshot.type, "snapshot");

    socket.send(JSON.stringify({ type: "injectHuman", to: "codex", message: "Please pause before commit." }));
    const event = await nextJson(socket);
    assert.equal(event.type, "message");
    const busMessage = event.message as Record<string, unknown>;
    assert.equal(busMessage.from, "human");

    const delivered = await state.awaitMessage("codex", 5);
    assert.equal(delivered?.from, "human");
    assert.equal(delivered?.message, "Please pause before commit.");
  } finally {
    socket.close();
    controlServer.close();
    await new Promise<void>((resolve, reject) => {
      httpServer.close((error) => (error ? reject(error) : resolve()));
    });
  }
});

test("control WebSocket rejects a loadSession id that is not a minted UUID", async () => {
  const state = new DuetState(config);
  const httpServer = createServer();
  const controlServer = attachControlServer(httpServer, state, config);
  await new Promise<void>((resolve) => httpServer.listen(0, "127.0.0.1", resolve));

  const address = httpServer.address();
  const port = (address as AddressInfo).port;
  const socket = new WebSocket(`ws://127.0.0.1:${port}/control`, {
    headers: { "X-Duet-Control-Token": config.controlToken },
  });

  try {
    assert.equal((await nextJson(socket)).type, "snapshot");

    socket.send(JSON.stringify({ type: "loadSession", sessionId: "../../../etc/passwd" }));
    const rejection = await nextJson(socket);
    assert.equal(rejection.type, "error");
    assert.equal(rejection.message, "Invalid control command.");

    // A well-formed but unknown id is accepted by the schema and answers with
    // an empty transcript rather than an error.
    socket.send(JSON.stringify({ type: "loadSession", sessionId: "6f1b3c9e-4d2a-4c5b-9f8e-1a2b3c4d5e6f" }));
    const empty = await nextJson(socket);
    assert.equal(empty.type, "sessionTranscript");
    assert.deepEqual(empty.transcript, []);
  } finally {
    socket.close();
    controlServer.close();
    await new Promise<void>((resolve, reject) => {
      httpServer.close((error) => (error ? reject(error) : resolve()));
    });
  }
});

test("control WebSocket rejects missing or wrong token before snapshot", async () => {
  const state = new DuetState(config);
  const httpServer = createServer();
  const controlServer = attachControlServer(httpServer, state, config);
  await new Promise<void>((resolve) => httpServer.listen(0, "127.0.0.1", resolve));

  const address = httpServer.address();
  assert.notEqual(address, null);
  assert.notEqual(typeof address, "string");
  const port = (address as AddressInfo).port;

  try {
    await assert.rejects(connectSocket(`ws://127.0.0.1:${port}/control`), /Unexpected server response: 401/);
    await assert.rejects(
      connectSocket(`ws://127.0.0.1:${port}/control?token=wrong-token`),
      /Unexpected server response: 401/,
    );
    await assert.rejects(
      connectSocket(`ws://127.0.0.1:${port}/control?token=${config.controlToken}`),
      /Unexpected server response: 401/,
    );
    const delivered = await state.awaitMessage("codex", 5);
    assert.equal(delivered, undefined);
  } finally {
    controlServer.close();
    await new Promise<void>((resolve, reject) => {
      httpServer.close((error) => (error ? reject(error) : resolve()));
    });
  }
});

test("control WebSocket rejects non-loopback origin even with a valid token", async () => {
  const state = new DuetState(config);
  const httpServer = createServer();
  const controlServer = attachControlServer(httpServer, state, config);
  await new Promise<void>((resolve) => httpServer.listen(0, "127.0.0.1", resolve));

  const address = httpServer.address();
  assert.notEqual(address, null);
  assert.notEqual(typeof address, "string");
  const port = (address as AddressInfo).port;

  try {
    await assert.rejects(
      connectSocket(`ws://127.0.0.1:${port}/control?token=${config.controlToken}`, {
        origin: "https://evil.example",
      }),
      /Unexpected server response: 403/,
    );
  } finally {
    controlServer.close();
    await new Promise<void>((resolve, reject) => {
      httpServer.close((error) => (error ? reject(error) : resolve()));
    });
  }
});

test("control WebSocket rate limits upgrade attempts", async () => {
  const limitedConfig = { ...config, maxRequestsPerMinute: 1 };
  const state = new DuetState(limitedConfig);
  const httpServer = createServer();
  const controlServer = attachControlServer(httpServer, state, limitedConfig);
  await new Promise<void>((resolve) => httpServer.listen(0, "127.0.0.1", resolve));

  const address = httpServer.address();
  assert.notEqual(address, null);
  assert.notEqual(typeof address, "string");
  const port = (address as AddressInfo).port;

  try {
    await assert.rejects(connectSocket(`ws://127.0.0.1:${port}/control`), /Unexpected server response: 401/);
    await assert.rejects(connectSocket(`ws://127.0.0.1:${port}/control`), /Unexpected server response: 429/);
  } finally {
    controlServer.close();
    await new Promise<void>((resolve, reject) => {
      httpServer.close((error) => (error ? reject(error) : resolve()));
    });
  }
});

test("control WebSocket closes after repeated invalid commands", async () => {
  const state = new DuetState(config);
  const httpServer = createServer();
  const controlServer = attachControlServer(httpServer, state, config);
  await new Promise<void>((resolve) => httpServer.listen(0, "127.0.0.1", resolve));

  const address = httpServer.address();
  assert.notEqual(address, null);
  assert.notEqual(typeof address, "string");
  const port = (address as AddressInfo).port;
  const socket = new WebSocket(`ws://127.0.0.1:${port}/control`, {
    headers: { "X-Duet-Control-Token": config.controlToken },
  });

  try {
    const snapshot = await nextJson(socket);
    assert.equal(snapshot.type, "snapshot");

    socket.send("{not-json");
    assert.equal((await nextJson(socket)).type, "error");
    socket.send("{not-json");
    assert.equal((await nextJson(socket)).type, "error");
    socket.send("{not-json");
    assert.equal((await nextJson(socket)).type, "error");
    const closeCode = await nextCloseCode(socket);
    assert.equal(closeCode, 1008);
  } finally {
    socket.close();
    controlServer.close();
    await new Promise<void>((resolve, reject) => {
      httpServer.close((error) => (error ? reject(error) : resolve()));
    });
  }
});

async function connectSocket(url: string, options: { origin?: string } = {}): Promise<WebSocket> {
  return await new Promise((resolve, reject) => {
    const socket = new WebSocket(url, options.origin ? { origin: options.origin } : undefined);
    socket.once("open", () => resolve(socket));
    socket.once("error", reject);
    socket.once("unexpected-response", (_request, response) => {
      reject(new Error(`Unexpected server response: ${response.statusCode}`));
    });
  });
}

async function nextJson(socket: WebSocket): Promise<Record<string, unknown>> {
  return await new Promise((resolve, reject) => {
    socket.once("message", (data) => {
      try {
        resolve(JSON.parse(data.toString()) as Record<string, unknown>);
      } catch (error) {
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    });
    socket.once("error", reject);
  });
}

async function nextCloseCode(socket: WebSocket): Promise<number> {
  return await new Promise((resolve, reject) => {
    socket.once("close", (code) => resolve(code));
    socket.once("error", reject);
  });
}
