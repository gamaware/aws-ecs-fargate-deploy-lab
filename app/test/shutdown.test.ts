// Runs the compiled entry point as a child process to prove the SIGTERM
// contract ECS relies on: /ready turns 503 at once, the process exits 0.

import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createServer } from "node:net";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";

const MAIN = fileURLToPath(new URL("../src/main.js", import.meta.url));

async function freePort(): Promise<number> {
  const probe = createServer();
  probe.listen(0, "127.0.0.1");
  await once(probe, "listening");
  const address = probe.address();
  probe.close();
  assert.ok(address !== null && typeof address === "object");
  return address.port;
}

describe("graceful shutdown", () => {
  it("drains on SIGTERM and exits 0", async () => {
    const port = await freePort();
    const child = spawn(process.execPath, [MAIN], {
      env: { PATH: process.env.PATH, PORT: String(port), SHUTDOWN_GRACE_SECONDS: "1" },
      stdio: ["ignore", "pipe", "inherit"],
    });
    let output = "";
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => {
      output += chunk;
    });
    const exited = once(child, "exit");

    for (let i = 0; i < 50 && !output.includes('"msg":"listening"'); i++) {
      await new Promise((r) => setTimeout(r, 50));
    }
    assert.match(output, /"msg":"listening"/);

    child.kill("SIGTERM");
    await new Promise((r) => setTimeout(r, 200));
    const ready = await fetch(`http://127.0.0.1:${port}/ready`);
    assert.equal(ready.status, 503);

    const [code] = await exited;
    assert.equal(code, 0);
    assert.match(output, /"msg":"draining"/);
    assert.match(output, /"msg":"stopped"/);
  });
});
