import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { AgentId } from "../types.js";
import type { DuetState } from "../state.js";

export function registerGetBriefingTool(server: McpServer, state: DuetState, agentId: AgentId): void {
  server.registerTool(
    "get_briefing",
    {
      title: "Get Duet Briefing",
      description: "Return this agent's role, peer, task, repository path, and coordination protocol.",
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    () => {
      const briefing = state.getBriefing(agentId);
      return {
        structuredContent: briefing,
        content: [{ type: "text", text: JSON.stringify(briefing, null, 2) }],
      };
    },
  );
}
