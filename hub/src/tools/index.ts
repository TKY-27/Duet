import { McpServer } from "@modelcontextprotocol/server";
import type { AgentId, DuetConfig } from "../types.js";
import type { DuetState } from "../state.js";
import { registerAwaitReplyTool } from "./awaitReply.js";
import { registerGetBriefingTool } from "./getBriefing.js";
import { registerSendTool } from "./send.js";

export function createAgentMcpServer(agentId: AgentId, state: DuetState, config: DuetConfig): McpServer {
  // No `logging` capability: the 2026-07-28 revision deprecates it. Hub
  // diagnostics go to stderr, which Duet.app already surfaces.
  const server = new McpServer({
    name: `duet-${agentId}`,
    version: "0.2.0",
  });
  registerGetBriefingTool(server, state, agentId);
  registerSendTool(server, state, agentId);
  registerAwaitReplyTool(server, state, agentId, config);
  return server;
}
