import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { randomBytes } from "node:crypto";
import { spawn, type ChildProcess } from "node:child_process";
import { createServer } from "node:net";
import WebSocket from "ws";

const controlToken = randomBytes(32).toString("base64url");

async function main(): Promise<void> {
  const port = await findOpenPort();
  const tempDir = mkdtempSync(path.join(tmpdir(), "duet-smoke-"));
  const repoPath = path.join(tempDir, "repo");
  const configPath = path.join(tempDir, "duet.config.json");
  mkdirSync(path.join(repoPath, ".git"), { recursive: true });
  writeFileSync(
    configPath,
    `${JSON.stringify(
      {
        host: "127.0.0.1",
        port,
        repoPath,
        holdSec: 5,
        noProgressHoldSec: 2,
        progressIntervalSec: 1,
        stallThresholdSec: 120,
        maxTranscriptMessages: 50,
        maxQueueMessages: 20,
        maxWaitersPerAgent: 5,
        maxTransports: 10,
        maxControlConnections: 2,
        maxRequestsPerMinute: 120,
        idleTransportTtlSec: 30,
      },
      null,
      2,
    )}\n`,
  );

  const child = spawn(process.execPath, [new URL("./server.js", import.meta.url).pathname, "--config", configPath], {
    cwd: path.resolve(".."),
    env: {
      ...process.env,
      DUET_CONTROL_TOKEN: controlToken,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });

  try {
    await waitForHealth(port, child);
    await waitForControlSnapshot(port);
  } finally {
    await stopChild(child);
    rmSync(tempDir, { recursive: true, force: true });
  }

  console.log("Hub smoke verified /health and control WebSocket snapshot.");
}

function findOpenPort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (typeof address !== "object" || !address) {
        server.close(() => reject(new Error("Could not allocate a smoke-test port.")));
        return;
      }
      const port = address.port;
      server.close((error) => (error ? reject(error) : resolve(port)));
    });
  });
}

async function waitForHealth(port: number, child: ChildProcess): Promise<void> {
  const url = `http://127.0.0.1:${port}/health`;
  let lastFailure = "no response";

  for (let attempt = 0; attempt < 80; attempt += 1) {
    if (child.exitCode !== null) {
      throw new Error(`Hub exited during smoke test with status ${child.exitCode}.`);
    }
    try {
      const response = await fetch(url);
      const body = (await response.json()) as { ok?: boolean; service?: string };
      if (response.ok && body.ok === true && body.service === "duet-hub") return;
      lastFailure = `HTTP ${response.status}`;
    } catch (error) {
      lastFailure = error instanceof Error ? error.message : String(error);
    }
    await delay(100);
  }

  throw new Error(`Hub health smoke check timed out: ${lastFailure}`);
}

function waitForControlSnapshot(port: number): Promise<void> {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(`ws://127.0.0.1:${port}/control`, {
      headers: { "X-Duet-Control-Token": controlToken },
    });
    const timeout = setTimeout(() => {
      socket.close();
      reject(new Error("Timed out waiting for control snapshot."));
    }, 5_000);

    socket.on("message", (payload) => {
      const event = JSON.parse(payload.toString()) as { type?: string; snapshot?: unknown };
      if (event.type === "snapshot" && event.snapshot) {
        clearTimeout(timeout);
        socket.close();
        resolve();
      }
    });
    socket.on("error", (error) => {
      clearTimeout(timeout);
      reject(error);
    });
  });
}

async function stopChild(child: ChildProcess): Promise<void> {
  if (child.exitCode !== null) return;
  child.kill("SIGTERM");
  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (child.exitCode !== null) return;
    await delay(50);
  }
  child.kill("SIGKILL");
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

void main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exit(1);
});
