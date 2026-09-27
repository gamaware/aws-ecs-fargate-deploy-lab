import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { loadConfig } from "../src/config.js";
import { createLogger } from "../src/logger.js";

describe("loadConfig", () => {
  it("uses defaults when nothing is set", () => {
    assert.deepEqual(loadConfig({}), { port: 8080, version: "dev", logLevel: "info", shutdownGraceSeconds: 10 });
  });

  it("reads every setting from the environment", () => {
    const config = loadConfig({ PORT: "3000", APP_VERSION: "1.2.3", LOG_LEVEL: "warn", SHUTDOWN_GRACE_SECONDS: "25" });
    assert.deepEqual(config, { port: 3000, version: "1.2.3", logLevel: "warn", shutdownGraceSeconds: 25 });
  });

  it("fails fast on invalid values", () => {
    assert.throws(() => loadConfig({ PORT: "eighty" }), /PORT must be an integer/);
    assert.throws(() => loadConfig({ PORT: "70000" }), /PORT must be between/);
    assert.throws(() => loadConfig({ LOG_LEVEL: "verbose" }), /LOG_LEVEL must be one of/);
    // Must stay below the ECS stopTimeout maximum of 120 seconds.
    assert.throws(() => loadConfig({ SHUTDOWN_GRACE_SECONDS: "300" }), /between 0 and 110/);
  });
});

describe("createLogger", () => {
  it("drops messages below the configured level", () => {
    const lines: string[] = [];
    const logger = createLogger("warn", (line) => lines.push(line));
    logger.info("ignored");
    logger.error("kept", { code: 7 });
    assert.equal(lines.length, 1);
    const entry = JSON.parse(lines[0] ?? "") as Record<string, unknown>;
    assert.equal(entry.level, "error");
    assert.equal(entry.code, 7);
  });
});
