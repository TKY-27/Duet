import { createApp } from "./dist/index.js";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";

const PORT = 8788;
const URL_STR = `http://127.0.0.1:${PORT}/mcp`;

async function call(client, name, args, opts) {
  const t0 = Date.now();
  try {
    const res = await client.callTool({ name, arguments: args }, undefined, opts);
    const dt = ((Date.now() - t0) / 1000).toFixed(1);
    const text = res?.content?.find((c) => c.type === "text")?.text ?? "";
    console.log(`OK   ${name}(${JSON.stringify(args)}) waited=${dt}s -> ${text}`);
  } catch (e) {
    const dt = ((Date.now() - t0) / 1000).toFixed(1);
    console.log(`FAIL ${name}(${JSON.stringify(args)}) waited=${dt}s -> ${e?.message || e}`);
  }
}

async function main() {
  const httpServer = await new Promise((resolve) => {
    const s = createApp().listen(PORT, "127.0.0.1", () => resolve(s));
  });
  console.log("[server] listening");

  const transport = new StreamableHTTPClientTransport(new URL(URL_STR));
  const client = new Client({ name: "inproc-test", version: "0.1.0" });
  await client.connect(transport);
  const tools = (await client.listTools()).tools.map((t) => t.name);
  console.log("[client] connected, tools:", tools.join(", "));

  await call(client, "ping", {});
  await call(client, "probe_block", { seconds: 2 }, { timeout: 60000 });
  await call(
    client,
    "probe_block_progress",
    { seconds: 4, everySec: 1 },
    { timeout: 2000, resetTimeoutOnProgress: true, maxTotalTimeout: 30000, onprogress: (p) => console.log(`   progress ${p.progress}/${p.total}`) }
  );
  await call(client, "probe_block", { seconds: 3 }, { timeout: 1000 });

  await client.close();
  httpServer.close();
  console.log("=== DONE ===");
  process.exit(0);
}

main().catch((e) => {
  console.error("test fatal:", e);
  process.exit(1);
});
