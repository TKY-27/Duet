/**
 * duet-timeout-spike
 *
 * A throwaway diagnostic MCP server (streamable HTTP) whose ONLY job is to answer:
 *   "How long will Codex.app / Claude Code (Claude Desktop) wait for a single tool
 *    response before their MCP client gives up — and does sending periodic progress
 *    notifications extend that window?"
 *
 * The two numbers it yields feed the real Duet hub's `await_reply`:
 *   - holdSec            (how long a single long-poll may safely block)
 *   - progress interval  (whether/how often to ping to stay alive)
 *
 * Register the SAME url in each app and test each independently:
 *   Claude Code:  claude mcp add-json spike '{"type":"http","url":"http://127.0.0.1:8799/mcp"}' -s user
 *   Codex:        [mcp_servers.spike]\n url = "http://127.0.0.1:8799/mcp"
 *
 * Everything is logged with timestamps to ./spike.log so that even when the CLIENT
 * times out you can see the SERVER completed the hold — that is how you distinguish a
 * client-side timeout from a real failure.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import type { RequestHandlerExtra } from "@modelcontextprotocol/sdk/shared/protocol.js";
import express from "express";
import { z } from "zod";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const PORT = parseInt(process.env.PORT || "8799", 10);
const LOG_FILE = path.join(process.cwd(), "spike.log");

function log(line: string): void {
  const msg = `[${new Date().toISOString()}] ${line}`;
  console.error(msg);
  try {
    fs.appendFileSync(LOG_FILE, msg + "\n");
  } catch {
    /* best-effort */
  }
}

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

function getProgressToken(
  extra: RequestHandlerExtra<any, any>
): string | number | undefined {
  const meta = (extra as { _meta?: { progressToken?: string | number } })._meta;
  return meta?.progressToken;
}

export function buildServer(): McpServer {
  const server = new McpServer({ name: "duet-timeout-spike", version: "0.1.0" });

  server.registerTool(
    "ping",
    {
      title: "Ping",
      description:
        "Returns immediately. Use first to confirm the app can reach this server at all.",
      inputSchema: {},
      outputSchema: { ok: z.boolean(), serverTime: z.string() },
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async () => {
      log("ping");
      const out = { ok: true, serverTime: new Date().toISOString() };
      return {
        content: [{ type: "text", text: JSON.stringify(out) }],
        structuredContent: out,
      };
    }
  );

  server.registerTool(
    "probe_block",
    {
      title: "Probe Block (no progress)",
      description:
        "Blocks server-side for `seconds`, then returns. Tests how long THIS app's MCP client " +
        "will wait for a single tool response before erroring. Call with escalating values " +
        "(10, 30, 45, 60, 90, 120, 180); the first value that errors client-side is past the " +
        "ceiling. Cross-check ./spike.log: a COMPLETE line for that value means the server " +
        "finished and the client timed out.",
      inputSchema: {
        seconds: z
          .number()
          .int()
          .min(0)
          .max(600)
          .describe("Seconds to block before responding (0-600)."),
      },
      outputSchema: {
        requestedSeconds: z.number(),
        heldMs: z.number(),
        completedAt: z.string(),
      },
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async ({ seconds }) => {
      const start = Date.now();
      log(`probe_block ARRIVE seconds=${seconds}`);
      await sleep(seconds * 1000);
      const heldMs = Date.now() - start;
      log(`probe_block COMPLETE seconds=${seconds} heldMs=${heldMs}`);
      const out = {
        requestedSeconds: seconds,
        heldMs,
        completedAt: new Date().toISOString(),
      };
      return {
        content: [{ type: "text", text: JSON.stringify(out) }],
        structuredContent: out,
      };
    }
  );

  server.registerTool(
    "probe_block_progress",
    {
      title: "Probe Block (with progress notifications)",
      description:
        "Blocks server-side for `seconds`, emitting an MCP progress notification every " +
        "`everySec` seconds. Many MCP clients reset their per-request timeout each time they " +
        "receive progress. Compare with probe_block: if probe_block dies at 60s but this " +
        "survives 180s+, periodic progress is how Duet's await_reply should stay alive. " +
        "`hadProgressToken=false` means this app did NOT request progress, so the technique " +
        "won't help for that app.",
      inputSchema: {
        seconds: z
          .number()
          .int()
          .min(0)
          .max(600)
          .describe("Total seconds to block (0-600)."),
        everySec: z
          .number()
          .int()
          .min(1)
          .max(60)
          .default(5)
          .describe("Emit a progress notification every N seconds (default 5)."),
      },
      outputSchema: {
        requestedSeconds: z.number(),
        heldMs: z.number(),
        progressSent: z.number(),
        hadProgressToken: z.boolean(),
        completedAt: z.string(),
      },
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async ({ seconds, everySec }, extra) => {
      const start = Date.now();
      const progressToken = getProgressToken(extra);
      const hadProgressToken =
        progressToken !== undefined && progressToken !== null;
      log(
        `probe_block_progress ARRIVE seconds=${seconds} everySec=${everySec} hadProgressToken=${hadProgressToken}`
      );

      let progressSent = 0;
      let elapsed = 0;
      while (elapsed < seconds) {
        const step = Math.min(everySec, seconds - elapsed);
        await sleep(step * 1000);
        elapsed += step;
        if (hadProgressToken) {
          try {
            await extra.sendNotification({
              method: "notifications/progress",
              params: {
                progressToken: progressToken!,
                progress: elapsed,
                total: seconds,
              },
            });
            progressSent++;
            log(`probe_block_progress PROGRESS elapsed=${elapsed}/${seconds}`);
          } catch (e) {
            log(`probe_block_progress PROGRESS_ERROR ${String(e)}`);
          }
        }
      }

      const heldMs = Date.now() - start;
      log(
        `probe_block_progress COMPLETE seconds=${seconds} heldMs=${heldMs} progressSent=${progressSent}`
      );
      const out = {
        requestedSeconds: seconds,
        heldMs,
        progressSent,
        hadProgressToken,
        completedAt: new Date().toISOString(),
      };
      return {
        content: [{ type: "text", text: JSON.stringify(out) }],
        structuredContent: out,
      };
    }
  );

  return server;
}

export function createApp(): express.Express {
  const app = express();
  app.use(express.json());

  app.get("/health", (_req, res) => {
    res.json({ ok: true, name: "duet-timeout-spike" });
  });

  // Stateless: fresh server + transport per request. SSE mode (no enableJsonResponse)
  // so progress notifications can flow mid-call.
  app.post("/mcp", async (req, res) => {
    const server = buildServer();
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined,
    });
    res.on("close", () => {
      void transport.close();
      void server.close();
    });
    try {
      await server.connect(transport);
      await transport.handleRequest(req, res, req.body);
    } catch (err) {
      log(`request error: ${String(err)}`);
      if (!res.headersSent) {
        res.status(500).json({ error: String(err) });
      }
    }
  });

  return app;
}

function startServer(): void {
  createApp().listen(PORT, "127.0.0.1", () => {
    log(`duet-timeout-spike listening on http://127.0.0.1:${PORT}/mcp`);
    log(`log file: ${LOG_FILE}`);
  });
}

const invokedDirectly =
  process.argv[1] !== undefined &&
  import.meta.url === pathToFileURL(process.argv[1]).href;
if (invokedDirectly) {
  startServer();
}
