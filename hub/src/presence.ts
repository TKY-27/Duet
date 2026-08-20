import { AGENT_IDS, type AgentId, type AgentPresenceSnapshot, type AgentStallSnapshot, type ControlEvent } from "./types.js";

export interface PresenceTrackerOptions {
  /** Seconds of silence after which an agent with no parked waiter looks stalled. */
  stallThresholdSec: number;
  /** Seconds of silence after which an agent is no longer considered connected. */
  presenceTtlSec: number;
  /** Whether the agent currently has a parked `await_reply`. */
  hasWaiter: (agentId: AgentId) => boolean;
}

/**
 * Observes whether each agent is reachable and whether it appears stuck.
 *
 * These are two different questions that the Hub answers from the same signal
 * (the timestamp of the agent's last MCP tool call):
 *
 * - *presence* — has this agent ever reached the Hub, and was that recent
 *   enough to still count as connected? The setup flow needs this to tell a
 *   half-configured client from a working one.
 * - *stall* — is a running agent silent while holding no `await_reply`? That
 *   combination means it has fallen out of the waiting loop, because a healthy
 *   waiting agent always has a waiter parked.
 *
 * Observation only: nothing here opens URLs, sends keystrokes, or wakes an app.
 */
export class PresenceTracker {
  private readonly lastActivityAt: Record<AgentId, number>;
  private readonly everSeen: Record<AgentId, boolean> = { claude: false, codex: false };
  private readonly stalled: Record<AgentId, boolean> = { claude: false, codex: false };
  private readonly connected: Record<AgentId, boolean> = { claude: false, codex: false };

  constructor(
    private readonly options: PresenceTrackerOptions,
    initialNowMs = Date.now(),
  ) {
    this.lastActivityAt = { claude: initialNowMs, codex: initialNowMs };
  }

  /** Records that `agentId` reached the Hub. Called on every MCP tool arrival. */
  recordActivity(agentId: AgentId, nowMs: number): void {
    this.lastActivityAt[agentId] = nowMs;
    this.everSeen[agentId] = true;
  }

  activityAgeMs(agentId: AgentId, nowMs: number): number {
    return Math.max(0, nowMs - this.lastActivityAt[agentId]);
  }

  isConnected(agentId: AgentId, nowMs: number): boolean {
    if (!this.everSeen[agentId]) return false;
    if (this.options.hasWaiter(agentId)) return true;
    return this.activityAgeMs(agentId, nowMs) <= this.options.presenceTtlSec * 1000;
  }

  isStalled(agentId: AgentId, nowMs: number): boolean {
    if (!this.everSeen[agentId]) return false;
    if (this.options.hasWaiter(agentId)) return false;
    return this.activityAgeMs(agentId, nowMs) > this.options.stallThresholdSec * 1000;
  }

  presenceSnapshots(nowMs: number): Record<AgentId, AgentPresenceSnapshot> {
    return {
      claude: this.presenceSnapshot("claude", nowMs),
      codex: this.presenceSnapshot("codex", nowMs),
    };
  }

  stallSnapshots(nowMs: number, running: boolean): Record<AgentId, AgentStallSnapshot> {
    return {
      claude: this.stallSnapshot("claude", nowMs, running),
      codex: this.stallSnapshot("codex", nowMs, running),
    };
  }

  /**
   * Returns the events for agents whose presence or stall state changed since
   * the last call, so the GUI is only notified on transitions.
   */
  evaluate(nowMs: number, running: boolean): ControlEvent[] {
    const events: ControlEvent[] = [];
    for (const agentId of AGENT_IDS) {
      const nextConnected = this.isConnected(agentId, nowMs);
      if (nextConnected !== this.connected[agentId]) {
        this.connected[agentId] = nextConnected;
        events.push({
          type: "presence",
          agentId,
          connected: nextConnected,
          everSeen: this.everSeen[agentId],
          sinceMs: this.activityAgeMs(agentId, nowMs),
        });
      }

      // A stopped room is not a stalled room: suppress stall transitions while
      // the human has paused the exchange.
      const nextStalled = running && this.isStalled(agentId, nowMs);
      if (nextStalled !== this.stalled[agentId]) {
        this.stalled[agentId] = nextStalled;
        events.push({
          type: "stall",
          agentId,
          stalled: nextStalled,
          sinceMs: this.activityAgeMs(agentId, nowMs),
        });
      }
    }
    return events;
  }

  /**
   * Clears stall state without forgetting that an agent was ever seen, and
   * returns the recovery events for the agents that were actually stalled.
   *
   * The caller must emit these. Duet.app also clears stalls when it sees
   * `status:false`, but that is the client inferring a state change the Hub
   * never announced — any other control client would keep showing a stall that
   * no longer exists. The Hub says what changed.
   */
  clearStalls(nowMs = Date.now()): ControlEvent[] {
    const events: ControlEvent[] = [];
    for (const agentId of AGENT_IDS) {
      if (!this.stalled[agentId]) continue;
      this.stalled[agentId] = false;
      events.push({ type: "stall", agentId, stalled: false, sinceMs: this.activityAgeMs(agentId, nowMs) });
    }
    return events;
  }

  private presenceSnapshot(agentId: AgentId, nowMs: number): AgentPresenceSnapshot {
    return {
      connected: this.isConnected(agentId, nowMs),
      everSeen: this.everSeen[agentId],
      sinceMs: this.activityAgeMs(agentId, nowMs),
    };
  }

  private stallSnapshot(agentId: AgentId, nowMs: number, running: boolean): AgentStallSnapshot {
    return {
      stalled: running && this.isStalled(agentId, nowMs),
      sinceMs: this.activityAgeMs(agentId, nowMs),
    };
  }
}
