import type { IncomingMessage, ServerResponse } from "node:http";

/**
 * Adapts a web-standard MCP handler (`handler.fetch`) to a Node request
 * handler, so the fetch-shaped v2 SDK entry point can be mounted on the
 * Hub's existing Express app.
 *
 * The official `@modelcontextprotocol/node` package offers the same
 * `toNodeHandler` conversion, but it depends on `@hono/node-server` and so
 * pulls Hono into Duet's production dependency tree. Duet serves four routes
 * from Express and needs none of that framework, so the conversion lives here
 * instead: it keeps the dependency surface (and its advisory stream) off a
 * local developer tool that never uses it.
 */
export type FetchHandler = (request: Request) => Promise<Response>;
export type NodeRequestHandler = (
  request: IncomingMessage,
  response: ServerResponse,
  parsedBody?: unknown,
) => Promise<void>;

export interface NodeHttpBridgeOptions {
  /** Reports conversion or handler failures before the 500 response is written. */
  onerror?: (error: Error) => void;
}

export function toNodeHandler(fetchHandler: FetchHandler, options: NodeHttpBridgeOptions = {}): NodeRequestHandler {
  return async (request, response, parsedBody) => {
    const abortController = new AbortController();
    // The peer hanging up must cancel the in-flight MCP exchange, otherwise a
    // held await_reply would keep waiting for a client that is already gone.
    const abortOnClose = (): void => {
      if (!response.writableEnded) abortController.abort();
    };
    request.on("aborted", abortOnClose);
    response.on("close", abortOnClose);

    try {
      const webRequest = toWebRequest(request, parsedBody, abortController.signal);
      const webResponse = await fetchHandler(webRequest);
      await writeWebResponse(webResponse, response);
    } catch (error) {
      const normalized = error instanceof Error ? error : new Error(String(error));
      options.onerror?.(normalized);
      if (!response.headersSent) {
        response.writeHead(500, { "content-type": "application/json" });
        response.end(JSON.stringify({ jsonrpc: "2.0", error: { code: -32603, message: "Internal server error" }, id: null }));
      } else {
        response.end();
      }
    } finally {
      request.off("aborted", abortOnClose);
      response.off("close", abortOnClose);
    }
  };
}

function toWebRequest(request: IncomingMessage, parsedBody: unknown, signal: AbortSignal): Request {
  const method = request.method ?? "GET";
  const headers = toWebHeaders(request);
  const url = new URL(request.url ?? "/", `http://${headers.get("host") ?? "127.0.0.1"}`);

  if (method === "GET" || method === "HEAD" || parsedBody === undefined) {
    return new Request(url, { method, headers, signal });
  }

  // Express has already read and parsed the body under the configured size
  // limit, so the original stream is consumed; re-serialize what it produced.
  const body = JSON.stringify(parsedBody);
  headers.set("content-type", "application/json");
  headers.delete("content-length");
  headers.delete("transfer-encoding");
  return new Request(url, { method, headers, body, signal });
}

function toWebHeaders(request: IncomingMessage): Headers {
  const headers = new Headers();
  for (const [name, value] of Object.entries(request.headers)) {
    if (value === undefined) continue;
    if (Array.isArray(value)) {
      for (const entry of value) headers.append(name, entry);
    } else {
      headers.set(name, value);
    }
  }
  return headers;
}

async function writeWebResponse(webResponse: Response, response: ServerResponse): Promise<void> {
  const headers: Record<string, string | string[]> = {};
  webResponse.headers.forEach((value, name) => {
    // set-cookie is the only header the Headers API intentionally joins; MCP
    // responses do not set it, but keep the split correct if one ever appears.
    headers[name] = name === "set-cookie" ? webResponse.headers.getSetCookie() : value;
  });
  response.writeHead(webResponse.status, headers);

  if (!webResponse.body) {
    response.end();
    return;
  }

  const reader = webResponse.body.getReader();
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      if (response.writableEnded) break;
      if (!response.write(value)) {
        // SSE keepalives can outrun a slow consumer; respect backpressure so
        // held await_reply streams do not buffer without bound.
        await once(response, "drain");
      }
    }
  } finally {
    reader.releaseLock();
    if (!response.writableEnded) response.end();
  }
}

function once(response: ServerResponse, event: "drain"): Promise<void> {
  return new Promise((resolve, reject) => {
    const onEvent = (): void => {
      response.off("error", onError);
      response.off("close", onEvent);
      resolve();
    };
    const onError = (error: Error): void => {
      response.off(event, onEvent);
      response.off("close", onEvent);
      reject(error);
    };
    response.once(event, onEvent);
    response.once("close", onEvent);
    response.once("error", onError);
  });
}
