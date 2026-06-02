import type { Server as HttpServer, IncomingMessage } from "node:http";
import { WebSocket, WebSocketServer } from "ws";
import * as z from "zod/v4";
import type { ControlEvent, DuetConfig, Roles } from "./types.js";
import type { DuetState } from "./state.js";
import { validateControlToken, validateLoopbackRequest } from "./security.js";

const RoleAssignmentSchema = z
  .object({
    role: z.string().trim().min(1).max(120),
    task: z.string().trim().max(4000),
  })
  .strict();

const SetRolesCommandSchema = z
  .object({
    type: z.literal("setRoles"),
    roles: z
      .object({
        claude: RoleAssignmentSchema.optional(),
        codex: RoleAssignmentSchema.optional(),
      })
      .strict(),
  })
  .strict();

const InjectHumanCommandSchema = z
  .object({
    type: z.literal("injectHuman"),
    to: z.enum(["claude", "codex", "both"]),
    message: z.string().trim().min(1).max(4000),
  })
  .strict();

const StartCommandSchema = z.object({ type: z.literal("start") }).strict();
const StopCommandSchema = z.object({ type: z.literal("stop") }).strict();

const ControlCommandSchema = z.discriminatedUnion("type", [
  SetRolesCommandSchema,
  InjectHumanCommandSchema,
  StartCommandSchema,
  StopCommandSchema,
]);

export function attachControlServer(
  server: HttpServer,
  state: DuetState,
  config: DuetConfig,
  controlPath = "/control",
): WebSocketServer {
  const wss = new WebSocketServer({ noServer: true, maxPayload: config.maxControlPayloadBytes });
  const upgradeLimiter = createControlRateLimiter(config);

  server.on("upgrade", (request, socket, head) => {
    const url = parseUrl(request);
    const pathname = url?.pathname;
    if (pathname !== controlPath) {
      socket.destroy();
      return;
    }
    if (!upgradeLimiter.allow(request)) {
      socket.write("HTTP/1.1 429 Too Many Requests\r\nConnection: close\r\n\r\n");
      socket.destroy();
      return;
    }
    if (wss.clients.size >= config.maxControlConnections) {
      socket.write("HTTP/1.1 503 Too Many Connections\r\nConnection: close\r\n\r\n");
      socket.destroy();
      return;
    }
    const denial =
      validateLoopbackRequest(request.headers, config) ?? validateControlToken(readToken(request, url), config);
    if (denial) {
      socket.write(`HTTP/1.1 ${denial.status} ${denial.message}\r\nConnection: close\r\n\r\n`);
      socket.destroy();
      return;
    }
    wss.handleUpgrade(request, socket, head, (socketInstance) => {
      wss.emit("connection", socketInstance, request);
    });
  });

  state.subscribe((event) => broadcast(wss, event));

  wss.on("connection", (socket) => {
    let invalidCommandCount = 0;
    sendJson(socket, { type: "snapshot", snapshot: state.snapshot() });
    socket.on("message", (raw) => {
      try {
        const command = ControlCommandSchema.parse(JSON.parse(raw.toString()));
        switch (command.type) {
          case "setRoles":
            state.setRoles(command.roles as Partial<Roles>);
            break;
          case "injectHuman":
            state.injectHuman(command.to, command.message);
            break;
          case "start":
            state.setRunning(true);
            break;
          case "stop":
            state.setRunning(false);
            break;
        }
      } catch (error) {
        invalidCommandCount += 1;
        const message = error instanceof Error ? error.message : String(error);
        console.warn(`Invalid control command: ${message}`);
        sendJson(socket, { type: "error", message: "Invalid control command." });
        if (invalidCommandCount >= 3) {
          socket.close(1008, "Too many invalid control commands.");
        }
      }
    });
  });

  return wss;
}

function parseUrl(request: IncomingMessage): URL | undefined {
  if (!request.url) return undefined;
  return new URL(request.url, "http://127.0.0.1");
}

function readToken(request: IncomingMessage, url: URL | undefined): string | undefined {
  void url;
  const header = request.headers["x-duet-control-token"];
  return typeof header === "string" ? header.trim() : undefined;
}

function createControlRateLimiter(config: DuetConfig): { allow(request: IncomingMessage): boolean } {
  const windows = new Map<string, { count: number; resetAt: number }>();
  return {
    allow(request: IncomingMessage): boolean {
      const key = request.socket.remoteAddress ?? "unknown";
      const now = Date.now();
      const window = windows.get(key);
      if (!window || window.resetAt <= now) {
        windows.set(key, { count: 1, resetAt: now + 60_000 });
        return true;
      }
      window.count += 1;
      return window.count <= config.maxRequestsPerMinute;
    },
  };
}

function broadcast(wss: WebSocketServer, event: ControlEvent): void {
  for (const client of wss.clients) {
    sendJson(client, event);
  }
}

function sendJson(socket: WebSocket, value: ControlEvent): void {
  if (socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(value));
  }
}
