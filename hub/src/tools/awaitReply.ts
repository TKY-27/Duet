import type { McpServer, ProgressNotification, ServerContext } from "@modelcontextprotocol/server";
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
    async ({ holdSec }, ctx: ServerContext) => {
      // A client that supplies a progress token has told us it will keep the
      // request alive while we send notifications, so we may hold for the full
      // holdSec. Without one we must return before the client's own timeout.
      //
      // A progress token is `string | number`, so `0` and `""` are legitimate
      // tokens: test for presence, never truthiness. The 2026-07-28 SDK client
      // numbers its tokens from 0, and a truthiness check there silently
      // collapses every hold to noProgressHoldSec.
      const rawProgressToken = ctx.mcpReq._meta?.progressToken;
      const progressToken = rawProgressToken === null ? undefined : rawProgressToken;
      const hasProgressToken = progressToken !== undefined;
      const requestedHoldSec = holdSec ?? config.holdSec;
      const effectiveHoldSec = hasProgressToken
        ? requestedHoldSec
        : Math.min(requestedHoldSec, config.noProgressHoldSec);
      let progressCount = 0;
      const progressInterval = hasProgressToken
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
            void ctx.mcpReq.notify(notification).catch((error: unknown) => {
              const message = error instanceof Error ? error.message : String(error);
              console.warn(`Could not send progress notification: ${message}`);
            });
          }, config.progressIntervalSec * 1000)
        : undefined;

      try {
        const message = await state.awaitMessage(agentId, effectiveHoldSec * 1000, ctx.mcpReq.signal);
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
