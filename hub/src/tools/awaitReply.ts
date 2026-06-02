import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { ProgressNotification } from "@modelcontextprotocol/sdk/types.js";
import * as z from "zod/v4";
import type { AgentId, DuetConfig } from "../types.js";
import type { DuetState } from "../state.js";

const AwaitReplyInputSchema = z
  .object({
    holdSec: z.number().int().min(1).max(300).optional().describe("Seconds to hold the request before returning empty."),
  })
  .strict();

export function registerAwaitReplyTool(
  server: McpServer,
  state: DuetState,
  agentId: AgentId,
  config: DuetConfig,
): void {
  server.registerTool(
    "await_reply",
    {
      title: "Await Duet Reply",
      description: "Wait for the next peer or human message. If empty is returned, call await_reply again.",
      inputSchema: AwaitReplyInputSchema,
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: true,
      },
    },
    async ({ holdSec }, extra) => {
      const progressToken = extra._meta?.progressToken;
      const requestedHoldSec = holdSec ?? config.holdSec;
      const effectiveHoldSec = progressToken
        ? requestedHoldSec
        : Math.min(requestedHoldSec, config.noProgressHoldSec);
      let progressCount = 0;
      const progressInterval = progressToken
        ? setInterval(() => {
            progressCount += 1;
            const notification: ProgressNotification = {
              method: "notifications/progress",
              params: {
                progressToken,
                progress: progressCount,
                message: `Duet is still waiting for a message for ${agentId}.`,
              },
            };
            void extra.sendNotification(notification).catch((error: unknown) => {
              const message = error instanceof Error ? error.message : String(error);
              console.warn(`Could not send progress notification: ${message}`);
            });
          }, config.progressIntervalSec * 1000)
        : undefined;

      try {
        const message = await state.awaitMessage(agentId, effectiveHoldSec * 1000, extra.signal);
        const result = state.toAwaitReplyResult(message);
        return {
          structuredContent: result,
          content: [{ type: "text", text: JSON.stringify(result) }],
        };
      } finally {
        if (progressInterval) clearInterval(progressInterval);
      }
    },
  );
}
