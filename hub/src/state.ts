import type {
  AgentId,
  AgentSendTarget,
  AwaitReplyResult,
  Briefing,
  BusMessage,
  ControlEvent,
  DuetConfig,
  MessageTarget,
  Recipient,
  RoleAssignment,
  Roles,
  SendResult,
  Snapshot,
} from "./types.js";
import { AGENT_IDS, peerOf } from "./types.js";
import { assertSafeCoordinationMessage, assertSafeRoleAssignment } from "./contentSafety.js";

interface Waiter {
  resolve: (message: BusMessage | undefined) => void;
  timeout: NodeJS.Timeout;
  abortHandler?: () => void;
  signal?: AbortSignal;
}

type StateListener = (event: ControlEvent) => void;
type QueueableMessage = BusMessage & { to: Recipient };

const PROTOCOL =
  "Call get_briefing first. Work on repoPath files directly; do not paste code into bus messages. " +
  "Use send for natural-language coordination, then await_reply. If await_reply returns empty, call await_reply again.";

export class DuetState {
  private readonly queues: Record<AgentId, BusMessage[]> = { claude: [], codex: [] };
  private readonly waiters: Record<AgentId, Waiter[]> = { claude: [], codex: [] };
  private readonly transcript: BusMessage[] = [];
  private readonly listeners = new Set<StateListener>();
  private readonly lastActivityAt: Record<AgentId, number>;
  private readonly stalled: Record<AgentId, boolean> = { claude: false, codex: false };
  private roles: Roles;
  private running = true;
  private seq = 0;
  private stallMonitor: NodeJS.Timeout | undefined;
  private stallMonitorIntervalMs: number | undefined;

  constructor(
    private readonly config: DuetConfig,
    initialNowMs = Date.now(),
  ) {
    this.roles = cloneRoles(config.roles);
    this.lastActivityAt = { claude: initialNowMs, codex: initialNowMs };
  }

  subscribe(listener: StateListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  getBriefing(agentId: AgentId): Briefing {
    const role = this.roles[agentId];
    return {
      agentId,
      role: role.role,
      peer: peerOf(agentId),
      task: role.task,
      repoPath: this.config.repoPath,
      protocol: PROTOCOL,
    };
  }

  sendFromAgent(from: AgentId, message: string, to: AgentSendTarget = "peer", activityAtMs = Date.now()): SendResult {
    if (!this.running) {
      throw new Error("Hub is stopped. Start the room before sending agent messages.");
    }
    if (to === "human") {
      const busMessage = this.createMessage("agent", from, "human", message);
      this.publishToHuman(busMessage);
      this.recordActivity(from, activityAtMs);
      return { status: "sent", seq: busMessage.seq };
    }
    const busMessage = this.createMessage("agent", from, peerOf(from), message);
    this.enqueue(busMessage, activityAtMs);
    this.recordActivity(from, activityAtMs);
    return { status: "sent", seq: busMessage.seq };
  }

  injectHuman(to: Recipient, message: string, activityAtMs = Date.now()): SendResult[] {
    const recipients = to === "both" ? AGENT_IDS : [to];
    const busMessages = recipients.map((recipient) => this.createMessage("human", "human", recipient, message));
    this.enqueueAll(busMessages, activityAtMs);
    return busMessages.map((busMessage) => ({ status: "sent", seq: busMessage.seq }));
  }

  async awaitMessage(
    agentId: AgentId,
    holdMs: number,
    signal?: AbortSignal,
    activityAtMs = Date.now(),
  ): Promise<BusMessage | undefined> {
    if (!this.running) return undefined;
    this.recordActivity(agentId, activityAtMs);
    const queued = this.queues[agentId].shift();
    if (queued) return queued;
    if (signal?.aborted) return undefined;
    if (this.waiters[agentId].length >= this.config.maxWaitersPerAgent) {
      throw new Error(`Too many pending await_reply calls for ${agentId}.`);
    }

    return await new Promise<BusMessage | undefined>((resolve) => {
      const waiter: Waiter = {
        resolve,
        timeout: setTimeout(() => {
          this.removeWaiter(agentId, waiter);
          resolve(undefined);
        }, holdMs),
        ...(signal ? { signal } : {}),
      };

      if (signal) {
        waiter.abortHandler = () => {
          this.removeWaiter(agentId, waiter);
          resolve(undefined);
        };
        signal.addEventListener("abort", waiter.abortHandler, { once: true });
      }

      this.waiters[agentId].push(waiter);
    });
  }

  setRoles(nextRoles: Partial<Roles>): Roles {
    const roles = {
      claude: nextRoles.claude ? cloneRole(nextRoles.claude) : cloneRole(this.roles.claude),
      codex: nextRoles.codex ? cloneRole(nextRoles.codex) : cloneRole(this.roles.codex),
    };
    assertSafeRoleAssignment("Claude", roles.claude);
    assertSafeRoleAssignment("Codex", roles.codex);
    this.roles = roles;
    this.emit({ type: "rolesUpdated", roles: cloneRoles(this.roles) });
    return cloneRoles(this.roles);
  }

  setRunning(running: boolean): void {
    this.running = running;
    if (!running) {
      this.stopStallMonitor();
      for (const agentId of AGENT_IDS) {
        this.stalled[agentId] = false;
      }
      for (const agentId of AGENT_IDS) {
        for (const waiter of [...this.waiters[agentId]]) {
          this.removeWaiter(agentId, waiter);
          waiter.resolve(undefined);
        }
      }
    } else if (this.stallMonitorIntervalMs !== undefined) {
      this.startStallMonitor(this.stallMonitorIntervalMs);
    }
    this.emit({ type: "status", running });
  }

  snapshot(nowMs = Date.now()): Snapshot {
    return {
      running: this.running,
      repoPath: this.config.repoPath,
      roles: cloneRoles(this.roles),
      transcript: this.transcript.map(cloneMessage),
      queues: {
        claude: this.queues.claude.length,
        codex: this.queues.codex.length,
      },
      holdSec: this.config.holdSec,
      noProgressHoldSec: this.config.noProgressHoldSec,
      progressIntervalSec: this.config.progressIntervalSec,
      stallThresholdSec: this.config.stallThresholdSec,
      stalls: this.stallSnapshots(nowMs),
    };
  }

  startStallMonitor(intervalMs = 5000): void {
    this.stallMonitorIntervalMs = intervalMs;
    if (!this.running || this.stallMonitor) return;
    this.stallMonitor = setInterval(() => {
      this.evaluateStalls(Date.now());
    }, intervalMs);
    this.stallMonitor.unref?.();
  }

  stopStallMonitor(): void {
    if (!this.stallMonitor) return;
    clearInterval(this.stallMonitor);
    this.stallMonitor = undefined;
  }

  evaluateStalls(nowMs: number): ControlEvent[] {
    if (!this.running) return [];
    const events: ControlEvent[] = [];
    for (const agentId of AGENT_IDS) {
      const sinceMs = this.activityAgeMs(agentId, nowMs);
      const nextStalled = this.isStalledAt(agentId, nowMs);
      if (nextStalled === this.stalled[agentId]) continue;
      this.stalled[agentId] = nextStalled;
      const event: ControlEvent = { type: "stall", agentId, stalled: nextStalled, sinceMs };
      events.push(event);
      this.emit(event);
    }
    return events;
  }

  toAwaitReplyResult(message: BusMessage | undefined): AwaitReplyResult {
    if (!message) {
      return {
        status: "empty",
        note: "No message yet. Call await_reply again to keep waiting.",
      };
    }
    return {
      status: "message",
      seq: message.seq,
      from: message.from,
      message: message.message,
      createdAt: message.createdAt,
    };
  }

  private createMessage<TTo extends MessageTarget>(
    kind: BusMessage["kind"],
    from: BusMessage["from"],
    to: TTo,
    message: string,
  ): BusMessage & { to: TTo } {
    const text = message.trim();
    if (!text) throw new Error("Message must not be empty.");
    if (text.length > 4000) throw new Error("Message must be 4000 characters or fewer.");
    assertSafeCoordinationMessage(text);
    this.seq += 1;
    return {
      seq: this.seq,
      kind,
      from,
      to,
      message: text,
      createdAt: new Date().toISOString(),
    };
  }

  private enqueue(message: QueueableMessage, activityAtMs: number): void {
    this.enqueueAll([message], activityAtMs);
  }

  private enqueueAll(messages: QueueableMessage[], activityAtMs: number): void {
    this.ensureQueueCapacityForMessages(messages);
    for (const message of messages) {
      this.appendTranscript(message);
    }
    for (const message of messages) {
      for (const recipient of recipientsFor(message.to)) {
        const waiter = this.waiters[recipient].shift();
        if (waiter) {
          clearTimeout(waiter.timeout);
          if (waiter.signal && waiter.abortHandler) {
            waiter.signal.removeEventListener("abort", waiter.abortHandler);
          }
          this.recordActivity(recipient, activityAtMs);
          waiter.resolve(cloneMessage(message));
        } else {
          this.ensureQueueCapacity(recipient);
          this.queues[recipient].push(cloneMessage(message));
        }
      }
    }
    for (const message of messages) {
      this.emit({ type: "message", message: cloneMessage(message) });
    }
  }

  private publishToHuman(message: BusMessage & { to: "human" }): void {
    this.appendTranscript(message);
    this.emit({ type: "message", message: cloneMessage(message) });
  }

  private ensureQueueCapacity(agentId: AgentId): void {
    if (this.queues[agentId].length >= this.config.maxQueueMessages) {
      throw new Error(`Queue for ${agentId} is full.`);
    }
  }

  private ensureQueueCapacityForMessages(messages: QueueableMessage[]): void {
    const availableWaiters: Record<AgentId, number> = {
      claude: this.waiters.claude.length,
      codex: this.waiters.codex.length,
    };
    const queuedMessages: Record<AgentId, number> = { claude: 0, codex: 0 };

    for (const message of messages) {
      for (const recipient of recipientsFor(message.to)) {
        if (availableWaiters[recipient] > 0) {
          availableWaiters[recipient] -= 1;
          continue;
        }
        queuedMessages[recipient] += 1;
        if (this.queues[recipient].length + queuedMessages[recipient] > this.config.maxQueueMessages) {
          throw new Error(`Queue for ${recipient} is full.`);
        }
      }
    }
  }

  private appendTranscript(message: BusMessage): void {
    this.transcript.push(cloneMessage(message));
    if (this.transcript.length > this.config.maxTranscriptMessages) {
      this.transcript.splice(0, this.transcript.length - this.config.maxTranscriptMessages);
    }
  }

  private removeWaiter(agentId: AgentId, waiter: Waiter): void {
    const waiters = this.waiters[agentId];
    const index = waiters.indexOf(waiter);
    if (index >= 0) waiters.splice(index, 1);
    clearTimeout(waiter.timeout);
    if (waiter.signal && waiter.abortHandler) {
      waiter.signal.removeEventListener("abort", waiter.abortHandler);
    }
  }

  private emit(event: ControlEvent): void {
    for (const listener of this.listeners) {
      listener(event);
    }
  }

  private recordActivity(agentId: AgentId, nowMs: number): void {
    this.lastActivityAt[agentId] = nowMs;
  }

  private stallSnapshots(nowMs: number): Record<AgentId, { stalled: boolean; sinceMs: number }> {
    return {
      claude: {
        stalled: this.running ? this.isStalledAt("claude", nowMs) : false,
        sinceMs: this.activityAgeMs("claude", nowMs),
      },
      codex: {
        stalled: this.running ? this.isStalledAt("codex", nowMs) : false,
        sinceMs: this.activityAgeMs("codex", nowMs),
      },
    };
  }

  private isStalledAt(agentId: AgentId, nowMs: number): boolean {
    return this.activityAgeMs(agentId, nowMs) > this.config.stallThresholdSec * 1000 && this.waiters[agentId].length === 0;
  }

  private activityAgeMs(agentId: AgentId, nowMs: number): number {
    return Math.max(0, nowMs - this.lastActivityAt[agentId]);
  }
}

function cloneRole(role: RoleAssignment): RoleAssignment {
  return { role: role.role, task: role.task };
}

function cloneRoles(roles: Roles): Roles {
  return {
    claude: cloneRole(roles.claude),
    codex: cloneRole(roles.codex),
  };
}

function cloneMessage(message: BusMessage): BusMessage {
  return { ...message };
}

function recipientsFor(to: Recipient): readonly AgentId[] {
  return to === "both" ? AGENT_IDS : [to];
}
