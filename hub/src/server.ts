import { createServer } from "node:http";
import express, { type NextFunction, type Request, type Response } from "express";
import { createMcpHandler, type McpHttpHandler } from "@modelcontextprotocol/server";
import { toNodeHandler } from "./nodeHttpBridge.js";
import { attachControlServer } from "./control.js";
import { loadConfig } from "./config.js";
import { redactControlEvent } from "./contentSafety.js";
import { validateControlToken, validateLoopbackRequest, validateMcpToken } from "./security.js";
import { DuetState } from "./state.js";
import { SessionStore } from "./store.js";
import { AGENT_IDS, type AgentId, type DuetConfig } from "./types.js";
import { createAgentMcpServer } from "./tools/index.js";

/**
 * The MCP handlers own no cross-request state: the 2026-07-28 revision made the
 * protocol stateless, and `legacy: "stateless"` serves 2025-era clients by
 * building a fresh server per request from the same factory. All shared state
 * lives in `DuetState`, so both eras see the same queues and transcript.
 */
export interface DuetHttpApp {
  app: express.Express;
  close: () => Promise<void>;
}

export function createDuetExpressApp(state: DuetState, config: DuetConfig): DuetHttpApp {
  const app = express();
  app.disable("x-powered-by");
  app.use((request, response, next) => {
    const denial = validateLoopbackRequest(request.headers, config);
    if (denial) {
      response.status(denial.status).send(denial.message);
      return;
    }
    next();
  });
  app.use(createRateLimiter(config));
  app.use(express.json({ limit: config.maxMcpPayloadBytes }));
  app.use(jsonErrorHandler);

  const handlers = new Map<AgentId, McpHttpHandler>();
  for (const agentId of AGENT_IDS) {
    handlers.set(agentId, attachMcpEndpoint(app, `/${agentId}`, agentId, state, config));
  }

  app.get("/health", (_request, response) => {
    response.json({
      ok: true,
      service: "duet-hub",
    });
  });

  app.get("/health/details", (request, response) => {
    const denial = validateControlToken(readControlTokenHeader(request), config);
    if (denial) {
      response.status(denial.status).json({ ok: false, error: denial.message });
      return;
    }
    const snapshot = state.snapshot();
    response.json({
      ok: true,
      service: "duet-hub",
      port: config.port,
      running: snapshot.running,
      repoPathConfigured: snapshot.repoPath.length > 0,
      queues: snapshot.queues,
      holdSec: snapshot.holdSec,
      noProgressHoldSec: snapshot.noProgressHoldSec,
      progressIntervalSec: snapshot.progressIntervalSec,
      roles: {
        claude: snapshot.roles.claude.role,
        codex: snapshot.roles.codex.role,
      },
    });
  });

  return {
    app,
    close: async () => {
      for (const handler of handlers.values()) {
        await handler.close();
      }
      handlers.clear();
    },
  };
}

function attachMcpEndpoint(
  app: express.Express,
  route: string,
  agentId: AgentId,
  state: DuetState,
  config: DuetConfig,
): McpHttpHandler {
  const handler = createMcpHandler(() => createAgentMcpServer(agentId, state, config), {
    legacy: "stateless",
    onerror: (error) => {
      console.error(`MCP ${agentId} handler error: ${error.message}`);
    },
  });
  const nodeHandler = toNodeHandler((request) => handler.fetch(request), {
    onerror: (error) => {
      console.error(`MCP ${agentId} adapter error: ${error.message}`);
    },
  });

  const serve = async (request: Request, response: Response): Promise<void> => {
    const denial = validateMcpToken(readMcpToken(request), agentId, config);
    if (denial) {
      sendJsonRpcError(response, denial.status, denial.message);
      return;
    }
    await nodeHandler(request, response, request.body);
  };

  for (const path of [route, `${route}/:token`]) {
    app.post(path, serve);
    app.get(path, serve);
    app.delete(path, serve);
  }
  app.all(route, (_request, response) => {
    response.status(401).send(mcpAuthMessage(route));
  });

  return handler;
}

function readRouteToken(request: Request): string | undefined {
  const token = request.params.token;
  return typeof token === "string" ? token : undefined;
}

function readMcpToken(request: Request): string | undefined {
  return readRouteToken(request) ?? readBearerToken(request);
}

function readBearerToken(request: Request): string | undefined {
  const header = request.headers.authorization;
  if (typeof header !== "string") return undefined;
  const [scheme, token, ...extra] = header.trim().split(/\s+/);
  if (extra.length > 0 || scheme?.toLowerCase() !== "bearer" || !token) return undefined;
  return token;
}

function mcpAuthMessage(route: string): string {
  return `MCP endpoint requires a per-agent token. Use Authorization: Bearer <token> on ${route}, or ${route}/<token> if your MCP client cannot set headers.`;
}

function sendJsonRpcError(response: Response, status: number, message: string): void {
  response.status(status).json({
    jsonrpc: "2.0",
    error: {
      code: -32000,
      message,
    },
    id: null,
  });
}

function readControlTokenHeader(request: Request): string | undefined {
  const header = request.headers["x-duet-control-token"];
  return typeof header === "string" ? header.trim() : undefined;
}

function createRateLimiter(config: DuetConfig): express.RequestHandler {
  const windows = new Map<string, { count: number; resetAt: number }>();
  return (request, response, next) => {
    const key = request.socket.remoteAddress ?? "unknown";
    const now = Date.now();
    const window = windows.get(key);
    if (!window || window.resetAt <= now) {
      windows.set(key, { count: 1, resetAt: now + 60_000 });
      next();
      return;
    }
    window.count += 1;
    if (window.count > config.maxRequestsPerMinute) {
      response.status(429).json({ ok: false, error: "Too many requests" });
      return;
    }
    next();
  };
}

function jsonErrorHandler(error: unknown, _request: Request, response: Response, next: NextFunction): void {
  if (!error) {
    next();
    return;
  }
  const rawStatus = typeof error === "object" && error !== null && "status" in error ? Number(error.status) : 400;
  const status = Number.isInteger(rawStatus) ? rawStatus : 400;
  const code = status === 413 ? 413 : 400;
  response.status(code).json({
    ok: false,
    error: code === 413 ? "Payload too large" : "Invalid JSON payload",
  });
}

async function main(): Promise<void> {
  const config = loadConfig();
  const state = new DuetState(config, Date.now(), new SessionStore());
  const { app, close: closeMcpHandlers } = createDuetExpressApp(state, config);
  const httpServer = createServer(app);
  const controlServer = attachControlServer(httpServer, state, config);
  state.startStallMonitor();
  state.startRepoMonitor();

  const verboseEvents = process.env.DUET_VERBOSE_EVENTS === "1";
  state.subscribe((event) => {
    if (verboseEvents) {
      console.log(JSON.stringify(redactControlEvent(event)));
      return;
    }
    if (event.type === "message") {
      console.log(
        JSON.stringify({
          type: "message",
          seq: event.message.seq,
          kind: event.message.kind,
          from: event.message.from,
          to: event.message.to,
          createdAt: event.message.createdAt,
        }),
      );
      return;
    }
    console.log(JSON.stringify({ type: event.type }));
  });

  await new Promise<void>((resolve) => {
    httpServer.listen(config.port, config.host, resolve);
  });

  console.log(`Duet Hub listening on http://${config.host}:${config.port}`);
  console.log(`MCP endpoints require per-agent tokens; control WebSocket: /control`);

  const shutdown = async (): Promise<void> => {
    state.stopStallMonitor();
    state.stopRepoMonitor();
    state.closeStore();
    await closeMcpHandlers();
    controlServer.close();
    await new Promise<void>((resolve, reject) => {
      httpServer.close((error) => (error ? reject(error) : resolve()));
    });
  };

  process.once("SIGINT", () => {
    void shutdown().finally(() => process.exit(0));
  });
  process.once("SIGTERM", () => {
    void shutdown().finally(() => process.exit(0));
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  void main().catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message);
    process.exit(1);
  });
}
