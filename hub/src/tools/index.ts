import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { AgentId, DuetConfig } from "../types.js";
import type { DuetState } from "../state.js";
import { registerAwaitReplyTool } from "./awaitReply.js";
import { registerGetBriefingTool } from "./getBriefing.js";
import { registerSendTool } from "./send.js";

export function createAgentMcpServer(agentId: AgentId, state: DuetState, config: DuetConfig): McpServer {
  const server = new McpServer(
    {
      name: `duet-${agentId}`,
      version: "0.1.0",
    },
    {
      capabilities: {
        logging: {},
        tools: {},
      },
    },
  );
  registerGetBriefingTool(server, state, agentId);
  registerSendTool(server, state, agentId);
  registerAwaitReplyTool(server, state, agentId, config);
  return server;
}
