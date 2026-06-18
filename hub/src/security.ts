import { timingSafeEqual } from "node:crypto";
import type { IncomingHttpHeaders } from "node:http";
import type { AgentId, DuetConfig } from "./types.js";

export interface RequestDenial {
  status: number;
  message: string;
}

// Periodically drop expired rate-limit windows so the map cannot grow unbounded when the
// Hub is exposed beyond loopback. unref so it never keeps the process alive.
export function startWindowEviction(windows: Map<string, { resetAt: number }>): void {
  const timer = setInterval(() => {
    const now = Date.now();
    for (const [key, window] of windows) {
      if (window.resetAt <= now) windows.delete(key);
    }
  }, 60_000);
  timer.unref?.();
}

export function validateLoopbackRequest(headers: IncomingHttpHeaders, config: DuetConfig): RequestDenial | undefined {
  if (!isAllowedHost(headers.host, config)) {
    return { status: 403, message: "Forbidden" };
  }
  if (!isAllowedOrigin(headers.origin, config)) {
    return { status: 403, message: "Forbidden" };
  }
  return undefined;
}

export function validateControlToken(actual: string | undefined, config: DuetConfig): RequestDenial | undefined {
  if (!actual || !tokensMatch(actual, config.controlToken)) {
    return { status: 401, message: "Unauthorized" };
  }
  return undefined;
}

export function validateMcpToken(
  actual: string | undefined,
  agentId: AgentId,
  config: DuetConfig,
): RequestDenial | undefined {
  if (!actual || !tokensMatch(actual, config.mcpTokens[agentId])) {
    return {
      status: 401,
      message: `MCP endpoint requires a per-agent token. Prefer Authorization: Bearer <token>; use /${agentId}/<token> only if your MCP client cannot set headers.`,
    };
  }
  return undefined;
}

function isAllowedHost(rawHost: string | string[] | undefined, config: DuetConfig): boolean {
  const host = singleHeaderValue(rawHost);
  if (!host) return false;
  return config.allowNonLoopbackHost || isLoopbackHost(extractHostname(host));
}

function isAllowedOrigin(rawOrigin: string | string[] | undefined, config: DuetConfig): boolean {
  const originHeader = singleHeaderValue(rawOrigin);
  if (!originHeader) return true;
  if (originHeader === "null") return false;
  try {
    const origin = new URL(originHeader);
    return config.allowNonLoopbackHost || isLoopbackHost(origin.hostname);
  } catch {
    return false;
  }
}

function singleHeaderValue(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function tokensMatch(actual: string, expected: string): boolean {
  const actualBytes = Buffer.from(actual);
  const expectedBytes = Buffer.from(expected);
  return actualBytes.length === expectedBytes.length && timingSafeEqual(actualBytes, expectedBytes);
}

function extractHostname(rawHost: string): string {
  if (rawHost.startsWith("[")) {
    const closingBracket = rawHost.indexOf("]");
    return closingBracket >= 0 ? rawHost.slice(1, closingBracket) : rawHost;
  }
  return rawHost.split(":")[0] ?? rawHost;
}

function isLoopbackHost(host: string): boolean {
  const normalized = host.toLowerCase();
  return normalized === "127.0.0.1" || normalized === "localhost" || normalized === "::1";
}
