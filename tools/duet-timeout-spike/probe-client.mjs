/**
 * probe-client.mjs — optional local driver for duet-timeout-spike.
 *
 * Measures THIS SDK client's behavior (NOT Codex.app / Claude Code). Use it only as a
 * sanity harness and to see the progress-keepalive trick. Real ceilings must be measured
 * from inside the apps themselves.
 *
 * Usage:
 *   node probe-client.mjs                       # quick self-test
 *   node probe-client.mjs block 60              # block 60s, generous client timeout
 *   node probe-client.mjs block 60 30           # block 60s with a HARD 30s timeout (should fail)
 *   node probe-client.mjs progress 120 5 30     # block 120s, progress every 5s, 30s base reset by progress
 *
 * Env: URL (default http://127.0.0.1:8799/mcp)
 */
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";

const URL_STR = process.env.URL || "http://127.0.0.1:8799/mcp";

async function main() {
  const [mode, aRaw, bRaw, cRaw] = process.argv.slice(2);
  const transport = new StreamableHTTPClientTransport(new URL(URL_STR));
  const client = new Client({ name: "probe-client", version: "0.1.0" });
  await client.connect(transport);

  const call = async (name, args, opts) => {
    const t0 = Date.now();
    try {
      const res = await client.callTool({ name, arguments: args }, undefined, opts);
      const dt = ((Date.now() - t0) / 1000).toFixed(1);
      const text = res?.content?.find((c) => c.type === "text")?.text ?? "";
      console.log(`OK   ${name}(${JSON.stringify(args)})  waited=${dt}s  -> ${text}`);
    } catch (e) {
      const dt = ((Date.now() - t0) / 1000).toFixed(1);
      console.log(`FAIL ${name}(${JSON.stringify(args)})  waited=${dt}s  -> ${e?.message || e}`);
    }
  };

  if (!mode) {
    await call("ping", {});
    await call("probe_block", { seconds: 2 }, { timeout: 60000 });
    await call(
      "probe_block_progress",
      { seconds: 4, everySec: 1 },
      { timeout: 2000, resetTimeoutOnProgress: true, onprogress: (p) => console.log(`   progress ${p.progress}/${p.total}`) }
    );
  } else if (mode === "block") {
    const seconds = parseInt(aRaw || "30", 10);
    const timeoutSec = bRaw ? parseInt(bRaw, 10) : seconds + 30;
    await call("probe_block", { seconds }, { timeout: timeoutSec * 1000 });
  } else if (mode === "progress") {
    const seconds = parseInt(aRaw || "60", 10);
    const everySec = bRaw ? parseInt(bRaw, 10) : 5;
    const baseTimeoutSec = cRaw ? parseInt(cRaw, 10) : 30;
    await call(
      "probe_block_progress",
      { seconds, everySec },
      {
        timeout: baseTimeoutSec * 1000,
        resetTimeoutOnProgress: true,
        maxTotalTimeout: (seconds + 60) * 1000,
        onprogress: (p) => console.log(`   progress ${p.progress}/${p.total}`),
      }
    );
  } else {
    console.log("unknown mode:", mode);
  }

  await client.close();
}

main().catch((e) => {
  console.error("client fatal:", e);
  process.exit(1);
});
