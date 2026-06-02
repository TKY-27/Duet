import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import type { AgentId } from "../types.js";
import type { DuetState } from "../state.js";

const SendInputSchema = z
  .object({
    message: z.string().trim().min(1).max(4000).describe("Natural-language coordination message. Do not paste code here."),
    to: z
      .literal("human")
      .optional()
      .describe("Optional explicit recipient. Omit this to send to the peer agent; set to human to update the GUI transcript only."),
  })
  .strict();

export function registerSendTool(server: McpServer, state: DuetState, agentId: AgentId): void {
  server.registerTool(
    "send",
    {
      title: "Send Coordination Message",
      description: "Send one natural-language coordination message to the peer agent, or explicitly to the human transcript.",
      inputSchema: SendInputSchema,
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: true,
      },
    },
    ({ message, to }) => {
      const result = state.sendFromAgent(agentId, message, to ?? "peer");
      return {
        structuredContent: result,
        content: [{ type: "text", text: JSON.stringify(result) }],
      };
    },
  );
}
