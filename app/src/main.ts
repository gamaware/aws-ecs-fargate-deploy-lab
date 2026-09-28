// Process entry point: start the server and shut down cleanly on SIGTERM,
// which ECS sends before it stops a task (then SIGKILL after stopTimeout).

import { loadConfig } from "./config.js";
import { createLogger } from "./logger.js";
import { createApp, type AppState } from "./server.js";

const config = loadConfig();
const logger = createLogger(config.logLevel);
const state: AppState = { version: config.version, draining: false };
const server = createApp(state, logger);

server.listen(config.port, () => {
  logger.info("listening", { port: config.port, version: config.version });
});

let stopping = false;

function shutdown(signal: string): void {
  if (stopping) {
    return;
  }
  stopping = true;
  state.draining = true;
  logger.info("draining", { signal, graceSeconds: config.shutdownGraceSeconds });
  setTimeout(() => {
    server.close((err) => {
      if (err) {
        logger.error("close failed", { error: err.message });
        process.exit(1);
      }
      logger.info("stopped");
      process.exit(0);
    });
    server.closeIdleConnections();
  }, config.shutdownGraceSeconds * 1000).unref();
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
