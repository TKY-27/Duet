import assert from "node:assert/strict";
import test from "node:test";
import { DuetState } from "./state.js";
import { redactSensitiveText } from "./contentSafety.js";
import type { ControlEvent, DuetConfig } from "./types.js";

const config: DuetConfig = {
  host: "127.0.0.1",
  port: 8765,
  repoPath: "/tmp/duet-test",
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

test("sendFromAgent delivers to the peer awaiter", async () => {
  const state = new DuetState(config);
  const waiting = state.awaitMessage("codex", 100);
  const sent = state.sendFromAgent("claude", "Please review src/auth.ts");
  const message = await waiting;

  assert.equal(sent.status, "sent");
  assert.equal(message?.from, "claude");
  assert.equal(message?.to, "codex");
  assert.equal(message?.message, "Please review src/auth.ts");
});

test("awaitMessage returns undefined after hold timeout", async () => {
  const state = new DuetState(config);
  const message = await state.awaitMessage("claude", 5);
  assert.equal(message, undefined);
});

test("injectHuman can fan out to both agents", async () => {
  const state = new DuetState(config);
  const results = state.injectHuman("both", "Pause after this review.");
  const claudeMessage = await state.awaitMessage("claude", 5);
  const codexMessage = await state.awaitMessage("codex", 5);

  assert.equal(results.length, 2);
  assert.equal(claudeMessage?.from, "human");
  assert.equal(codexMessage?.from, "human");
  assert.equal(claudeMessage?.message, "Pause after this review.");
  assert.equal(codexMessage?.message, "Pause after this review.");
});

test("injectHuman both resolves a waiting agent and queues the other atomically", async () => {
  const state = new DuetState(config);
  const claudeWaiting = state.awaitMessage("claude", 1000);

  const results = state.injectHuman("both", "Pause and report current status.");
  const claudeMessage = await claudeWaiting;
  const codexMessage = await state.awaitMessage("codex", 5);

  assert.equal(results.length, 2);
  assert.equal(claudeMessage?.from, "human");
  assert.equal(claudeMessage?.to, "claude");
  assert.equal(claudeMessage?.message, "Pause and report current status.");
  assert.equal(codexMessage?.from, "human");
  assert.equal(codexMessage?.to, "codex");
  assert.equal(codexMessage?.message, "Pause and report current status.");
});

test("injectHuman both rejects unsafe messages without enqueueing either side", async () => {
  const state = new DuetState(config);
  const claudeWaiting = state.awaitMessage("claude", 5);
  const codexWaiting = state.awaitMessage("codex", 5);

  assert.throws(() => state.injectHuman("both", "```ts\nconst token = 1;\n```"), /code block/);

  const snapshot = state.snapshot();
  assert.equal(snapshot.transcript.length, 0);
  assert.deepEqual(snapshot.queues, { claude: 0, codex: 0 });
  assert.equal(await claudeWaiting, undefined);
  assert.equal(await codexWaiting, undefined);
});

test("sendFromAgent can publish to human without resolving awaiters", async () => {
  const state = new DuetState(config);
  const events: ControlEvent[] = [];
  state.subscribe((event) => events.push(event));
  const claudeWaiting = state.awaitMessage("claude", 10);
  const codexWaiting = state.awaitMessage("codex", 10);

  const sent = state.sendFromAgent("claude", "I paused before committing.", "human");
  const snapshot = state.snapshot();

  assert.equal(sent.status, "sent");
  assert.equal(snapshot.transcript.length, 1);
  assert.equal(snapshot.transcript[0]?.kind, "agent");
  assert.equal(snapshot.transcript[0]?.from, "claude");
  assert.equal(snapshot.transcript[0]?.to, "human");
  assert.equal(snapshot.transcript[0]?.message, "I paused before committing.");
  assert.equal(events.length, 1);
  assert.equal(events[0]?.type, "message");
  assert.deepEqual(snapshot.queues, { claude: 0, codex: 0 });
  assert.equal(await claudeWaiting, undefined);
  assert.equal(await codexWaiting, undefined);
});

test("stop resolves pending awaiters and blocks agent sends", async () => {
  const state = new DuetState(config);
  const waiting = state.awaitMessage("codex", 1000);

  state.setRunning(false);

  const message = await waiting;
  assert.equal(message, undefined);
  assert.throws(() => state.sendFromAgent("claude", "This should not send."), /Hub is stopped/);
});

test("an agent that never reached the Hub is reported absent, not stalled", () => {
  // A fresh Hub must not accuse agents of stalling before they have ever
  // connected: on launch that would warn about a room the human has not wired
  // up yet. Absence is a presence fact, not a stall.
  const state = new DuetState(config, 0);
  const events = state.evaluateStalls(config.stallThresholdSec * 1000 + 1);

  assert.deepEqual(events, []);
  const snapshot = state.snapshot(config.stallThresholdSec * 1000 + 1);
  assert.equal(snapshot.stalls.claude.stalled, false);
  assert.equal(snapshot.presence.claude.connected, false);
  assert.equal(snapshot.presence.claude.everSeen, false);
});

test("stall evaluation marks a previously seen, inactive agent with no waiter as stalled", () => {
  const state = new DuetState(config, 0);
  // Both agents check in, then go quiet without re-arming await_reply.
  state.sendFromAgent("claude", "Starting work.", "human", 1);
  state.sendFromAgent("codex", "Standing by.", "human", 1);

  const events = state.evaluateStalls(config.stallThresholdSec * 1000 + 2);
  const stallEvents = events.filter((event) => event.type === "stall");

  assert.deepEqual(
    stallEvents.map((event) => event.type),
    ["stall", "stall"],
  );
  assert.deepEqual(
    stallEvents.map((event) => {
      assert.equal(event.type, "stall");
      return event.stalled;
    }),
    [true, true],
  );
  assert.equal(state.snapshot(config.stallThresholdSec * 1000 + 2).stalls.claude.stalled, true);
});

test("presence flips to connected on first contact and back after the TTL", () => {
  const state = new DuetState(config, 0);
  const connectEvents = state.evaluateStalls(1);
  assert.deepEqual(connectEvents, []);

  state.sendFromAgent("claude", "Briefing received.", "human", 2);
  const seenEvents = state.evaluateStalls(3).filter((event) => event.type === "presence");
  assert.equal(seenEvents.length, 1);
  assert.equal(seenEvents[0]?.type === "presence" && seenEvents[0].connected, true);

  const expiredAt = config.presenceTtlSec * 1000 + 10;
  const lostEvents = state.evaluateStalls(expiredAt).filter((event) => event.type === "presence");
  assert.equal(lostEvents.length, 1);
  assert.equal(lostEvents[0]?.type === "presence" && lostEvents[0].connected, false);
  assert.equal(state.snapshot(expiredAt).presence.claude.everSeen, true);
});

test("stall evaluation does not mark agents stalled while waiters are present", async () => {
  const state = new DuetState(config, 0);
  const claudeWaiting = state.awaitMessage("claude", 1000, undefined, 1);
  const codexWaiting = state.awaitMessage("codex", 1000, undefined, 1);

  const events = state.evaluateStalls(config.stallThresholdSec * 1000 * 10);

  // A parked waiter proves the agent is still in the loop, so no stall is
  // reported however long the silence runs. (Presence events do fire here:
  // await_reply is itself contact with the Hub.)
  assert.equal(events.filter((event) => event.type === "stall").length, 0);
  assert.equal(state.snapshot(config.stallThresholdSec * 1000 * 10).stalls.claude.stalled, false);
  assert.equal(state.snapshot(config.stallThresholdSec * 1000 * 10).stalls.codex.stalled, false);

  state.setRunning(false);
  assert.equal(await claudeWaiting, undefined);
  assert.equal(await codexWaiting, undefined);
});

test("stall evaluation emits one recovery event after await_reply re-arms", async () => {
  const state = new DuetState(config, 0);
  state.sendFromAgent("claude", "Starting work.", "human", 1);
  state.sendFromAgent("codex", "Standing by.", "human", 1);
  const firstEvents = state.evaluateStalls(config.stallThresholdSec * 1000 + 2);
  assert.equal(firstEvents.filter((event) => event.type === "stall" && event.stalled).length, 2);

  const waiting = state.awaitMessage("claude", 1000, undefined, config.stallThresholdSec * 1000 + 3);
  const recoveryEvents = state
    .evaluateStalls(config.stallThresholdSec * 1000 + 3)
    .filter((event) => event.type === "stall");
  const repeatedEvents = state.evaluateStalls(config.stallThresholdSec * 1000 + 4);

  assert.deepEqual(recoveryEvents, [
    {
      type: "stall",
      agentId: "claude",
      stalled: false,
      sinceMs: 0,
    },
  ]);
  assert.equal(repeatedEvents.length, 0);

  state.setRunning(false);
  assert.equal(await waiting, undefined);
});

test("snapshot retains only the newest transcript messages", () => {
  const state = new DuetState({ ...config, maxTranscriptMessages: 2 });
  state.sendFromAgent("claude", "first");
  state.sendFromAgent("claude", "second");
  state.sendFromAgent("claude", "third");

  const transcript = state.snapshot().transcript;
  assert.equal(transcript.length, 2);
  assert.deepEqual(
    transcript.map((message) => message.message),
    ["second", "third"],
  );
});

test("queue capacity rejects additional messages without partial fanout", async () => {
  const state = new DuetState({ ...config, maxQueueMessages: 1 });
  state.injectHuman("both", "first");

  assert.throws(() => state.injectHuman("both", "second"), /Queue for claude is full/);

  const claudeMessage = await state.awaitMessage("claude", 5);
  const codexMessage = await state.awaitMessage("codex", 5);
  assert.equal(claudeMessage?.message, "first");
  assert.equal(codexMessage?.message, "first");
  assert.equal(await state.awaitMessage("claude", 5), undefined);
  assert.equal(await state.awaitMessage("codex", 5), undefined);
});

test("waiter capacity rejects excess awaiters", async () => {
  const state = new DuetState({ ...config, maxWaitersPerAgent: 1 });
  const firstWaiter = state.awaitMessage("codex", 100);

  await assert.rejects(state.awaitMessage("codex", 100), /Too many pending await_reply calls/);
  state.sendFromAgent("claude", "release waiter");
  const message = await firstWaiter;
  assert.equal(message?.message, "release waiter");
});

test("messages reject code blocks and secret-like values", () => {
  const state = new DuetState(config);
  assert.throws(() => state.sendFromAgent("claude", "```ts\nconst x = 1;\n```"), /code block/);
  assert.throws(() => state.injectHuman("codex", "api_key = sk-testsecret1234567890"), /secret/);
});

test("role updates reject code and secret-like task content", () => {
  const state = new DuetState(config);

  assert.throws(
    () =>
      state.setRoles({
        claude: {
          role: "implementer",
          task: "```ts\nconst secret = 1;\n```",
        },
      }),
    /code block/,
  );
  assert.throws(
    () =>
      state.setRoles({
        codex: {
          role: "reviewer",
          task: "api_key = sk-testsecret1234567890",
        },
      }),
    /secret/,
  );
});

test("redaction removes repeated same-pattern secrets", () => {
  const redacted = redactSensitiveText(
    "api_key = sk-firstsecret1234567890 password = secondsecret1234567890",
  );

  assert.equal(redacted.includes("sk-firstsecret1234567890"), false);
  assert.equal(redacted.includes("secondsecret1234567890"), false);
});

test("stopping the room announces stall recovery instead of clearing it silently", () => {
  const state = new DuetState(config, 0);
  state.sendFromAgent("claude", "Starting work.", "human", 1);
  state.sendFromAgent("codex", "Standing by.", "human", 1);
  const stalled = state
    .evaluateStalls(config.stallThresholdSec * 1000 + 2)
    .filter((event) => event.type === "stall" && event.stalled);
  assert.equal(stalled.length, 2);

  const events: ControlEvent[] = [];
  const unsubscribe = state.subscribe((event) => events.push(event));
  state.setRunning(false);
  unsubscribe();

  // A control client must not have to infer from `status:false` that stalls
  // are over: the Hub says so for each agent that was actually stalled.
  const recoveries = events.filter((event) => event.type === "stall");
  assert.equal(recoveries.length, 2);
  assert.ok(recoveries.every((event) => event.type === "stall" && !event.stalled));
  assert.deepEqual(
    recoveries.map((event) => (event.type === "stall" ? event.agentId : "")).sort(),
    ["claude", "codex"],
  );
  // And the status event still follows, after the recoveries.
  assert.equal(events.at(-1)?.type, "status");
});

test("stopping a room with no stalled agent emits no stall events", () => {
  const state = new DuetState(config, 0);
  const events: ControlEvent[] = [];
  const unsubscribe = state.subscribe((event) => events.push(event));
  state.setRunning(false);
  unsubscribe();

  assert.equal(events.filter((event) => event.type === "stall").length, 0);
});
