export const AGENT_IDS = ["claude", "codex"] as const;
export type AgentId = (typeof AGENT_IDS)[number];
export type Recipient = AgentId | "both";
export type MessageTarget = AgentId | "human" | "both";
export type MessageOrigin = AgentId | "human" | "system";
export type AgentSendTarget = "peer" | "human";

export interface RoleAssignment {
  role: string;
  task: string;
}

export type Roles = Record<AgentId, RoleAssignment>;

export interface DuetConfig {
  host: string;
  port: number;
  repoPath: string;
  roles: Roles;
  mcpTokens: Record<AgentId, string>;
  holdSec: number;
  noProgressHoldSec: number;
  progressIntervalSec: number;
  stallThresholdSec: number;
  controlToken: string;
  allowNonLoopbackHost: boolean;
  allowUnsafeRepoPath: boolean;
  maxTranscriptMessages: number;
  maxQueueMessages: number;
  maxWaitersPerAgent: number;
  maxTransports: number;
  maxMcpPayloadBytes: number;
  maxControlPayloadBytes: number;
  maxControlConnections: number;
  maxRequestsPerMinute: number;
  idleTransportTtlSec: number;
  configPath?: string;
  secretsPath: string;
  projectRoot: string;
}

export interface Briefing extends Record<string, unknown> {
  agentId: AgentId;
  role: string;
  peer: AgentId;
  task: string;
  repoPath: string;
  protocol: string;
}

export type BusMessageKind = "agent" | "human" | "system";

export interface BusMessage {
  seq: number;
  kind: BusMessageKind;
  from: MessageOrigin;
  to: MessageTarget;
  message: string;
  createdAt: string;
}

export interface AwaitEmpty extends Record<string, unknown> {
  status: "empty";
  note: string;
}

export interface AwaitMessage extends Record<string, unknown> {
  status: "message";
  seq: number;
  from: MessageOrigin;
  message: string;
  createdAt: string;
}

export type AwaitReplyResult = AwaitEmpty | AwaitMessage;

export interface SendResult extends Record<string, unknown> {
  status: "sent";
  seq: number;
}

export interface Snapshot {
  running: boolean;
  repoPath: string;
  branch: string;
  roles: Roles;
  transcript: BusMessage[];
  queues: Record<AgentId, number>;
  holdSec: number;
  noProgressHoldSec: number;
  progressIntervalSec: number;
  stallThresholdSec: number;
  stalls: Record<AgentId, AgentStallSnapshot>;
}

export interface AgentStallSnapshot {
  stalled: boolean;
  sinceMs: number;
}

export type ControlEvent =
  | { type: "snapshot"; snapshot: Snapshot }
  | { type: "message"; message: BusMessage }
  | { type: "rolesUpdated"; roles: Roles }
  | { type: "status"; running: boolean }
  | { type: "stall"; agentId: AgentId; stalled: boolean; sinceMs: number }
  | { type: "error"; message: string };

export function peerOf(agentId: AgentId): AgentId {
  return agentId === "claude" ? "codex" : "claude";
}

export function isAgentId(value: string): value is AgentId {
  return (AGENT_IDS as readonly string[]).includes(value);
}
