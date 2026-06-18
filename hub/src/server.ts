import { randomUUID } from "node:crypto";
import { createServer } from "node:http";
import express, { type NextFunction, type Request, type Response } from "express";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { isInitializeRequest } from "@modelcontextprotocol/sdk/types.js";
import { attachControlServer } from "./control.js";
import { loadConfig } from "./config.js";
import { redactControlEvent } from "./contentSafety.js";
import {
  startWindowEviction,
  validateControlToken,
  validateLoopbackRequest,
  validateMcpToken,
} from "./security.js";
import { DuetState } from "./state.js";
import type { AgentId, DuetConfig } from "./types.js";
import { createAgentMcpServer } from "./tools/index.js";

interface TransportRecord {
  transport: StreamableHTTPServerTransport;
  lastSeen: number;
}

const transports = new Map<string, TransportRecord>();

export function createDuetExpressApp(state: DuetState, config: DuetConfig): express.Express {
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

  attachMcpEndpoint(app, "/claude", "claude", state, config);
  attachMcpEndpoint(app, "/codex", "codex", state, config);

  app.get("/health", (_request, response) => {
    response.json({
      ok: true,
      service: "duet-hub",
    });
  });

  // Returns ready-to-paste MCP registration commands with the real per-agent tokens.
  // Control-token gated and served only over loopback so tokens never travel the WS
  // broadcast channel the transcript flows on.
  app.get("/setup", (request, response) => {
    const denial = validateControlToken(readControlTokenHeader(request), config);
    if (denial) {
      response.status(denial.status).json({ ok: false, error: denial.message });
      return;
    }
    const base = `http://${config.host}:${config.port}`;
    const claudeJson = JSON.stringify({
      type: "http",
      url: `${base}/claude`,
      headers: { Authorization: `Bearer ${config.mcpTokens.claude}` },
    });
    response.json({
      ok: true,
      claudeCommand: `claude mcp add-json duet '${claudeJson}' -s user`,
      codexCommand:
        `export DUET_CODEX_MCP_TOKEN="${config.mcpTokens.codex}"\n` +
        `codex mcp add duet --url ${base}/codex --bearer-token-env-var DUET_CODEX_MCP_TOKEN`,
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

  return app;
}

function attachMcpEndpoint(
  app: express.Express,
  route: string,
  agentId: AgentId,
  state: DuetState,
  config: DuetConfig,
): void {
  app.post(route, async (request, response) => {
    await handleMcpPost(request, response, agentId, state, config);
  });
  app.get(route, async (request, response) => {
    await handleMcpSessionRequest(request, response, agentId, config);
  });
  app.delete(route, async (request, response) => {
    await handleMcpSessionRequest(request, response, agentId, config);
  });
  app.all(route, (_request, response) => {
    response.status(401).send(mcpAuthMessage(route));
  });
  const authenticatedRoute = `${route}/:token`;
  app.post(authenticatedRoute, async (request, response) => {
    await handleMcpPost(request, response, agentId, state, config);
  });
  app.get(authenticatedRoute, async (request, response) => {
    await handleMcpSessionRequest(request, response, agentId, config);
  });
  app.delete(authenticatedRoute, async (request, response) => {
    await handleMcpSessionRequest(request, response, agentId, config);
  });
}

async function handleMcpPost(
  request: Request,
  response: Response,
  agentId: AgentId,
  state: DuetState,
  config: DuetConfig,
): Promise<void> {
  try {
    const denial = validateMcpToken(readMcpToken(request), agentId, config);
    if (denial) {
      sendJsonRpcError(response, denial.status, denial.message);
      return;
    }
    pruneIdleTransports(config);
    const sessionId = readSessionId(request);
    if (sessionId) {
      const record = transports.get(transportKey(agentId, sessionId));
      if (!record) {
        sendJsonRpcError(response, 404, "Session not found");
        return;
      }
      record.lastSeen = Date.now();
      await record.transport.handleRequest(request, response, request.body);
      return;
    }

    if (!isInitializeRequest(request.body)) {
      sendJsonRpcError(response, 400, "Bad Request: missing MCP session id or initialize request");
      return;
    }
    if (transports.size >= config.maxTransports) {
      sendJsonRpcError(response, 503, "MCP session capacity reached");
      return;
    }

    let initializedSessionId: string | undefined;
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: () => randomUUID(),
      onsessioninitialized: (newSessionId) => {
        initializedSessionId = newSessionId;
        transports.set(transportKey(agentId, newSessionId), { transport, lastSeen: Date.now() });
      },
    });

    transport.onclose = () => {
      const sessionToDelete = transport.sessionId ?? initializedSessionId;
      if (sessionToDelete) transports.delete(transportKey(agentId, sessionToDelete));
    };

    const mcpServer = createAgentMcpServer(agentId, state, config);
    await mcpServer.connect(transport);
    await transport.handleRequest(request, response, request.body);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`MCP ${agentId} request failed: ${message}`);
    if (!response.headersSent) {
      sendJsonRpcError(response, 500, "Internal server error");
    }
  }
}

async function handleMcpSessionRequest(
  request: Request,
  response: Response,
  agentId: AgentId,
  config: DuetConfig,
): Promise<void> {
  const denial = validateMcpToken(readMcpToken(request), agentId, config);
  if (denial) {
    response.status(denial.status).send(denial.message);
    return;
  }
  pruneIdleTransports(config);
  const sessionId = readSessionId(request);
  if (!sessionId) {
    response.status(400).send("Invalid or missing MCP session id");
    return;
  }
  const record = transports.get(transportKey(agentId, sessionId));
  if (!record) {
    response.status(404).send("MCP session not found");
    return;
  }
  record.lastSeen = Date.now();
  await record.transport.handleRequest(request, response);
}

function readSessionId(request: Request): string | undefined {
  const header = request.headers["mcp-session-id"];
  return typeof header === "string" ? header : undefined;
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

function transportKey(agentId: AgentId, sessionId: string): string {
  return `${agentId}:${sessionId}`;
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
  startWindowEviction(windows);
  return (request, response, next) => {
    // Key by remote address AND route bucket so the two agents and the health plane each
    // get an independent budget. On loopback every client shares 127.0.0.1, so a chatty
    // agent must not be able to exhaust the peer's allowance from one shared bucket.
    const key = `${request.socket.remoteAddress ?? "unknown"}:${routeBucket(request.path)}`;
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

function routeBucket(pathname: string): string {
  return pathname.split("/")[1] || "root";
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

function pruneIdleTransports(config: DuetConfig): void {
  const cutoff = Date.now() - config.idleTransportTtlSec * 1000;
  for (const [key, record] of transports) {
    if (record.lastSeen >= cutoff) continue;
    transports.delete(key);
    void record.transport.close().catch(() => {});
  }
}

async function main(): Promise<void> {
  const config = loadConfig();
  const state = new DuetState(config);
  const app = createDuetExpressApp(state, config);
  const httpServer = createServer(app);
  const controlServer = attachControlServer(httpServer, state, config);
  state.startStallMonitor();

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
    for (const record of transports.values()) {
      await record.transport.close();
    }
    transports.clear();
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
