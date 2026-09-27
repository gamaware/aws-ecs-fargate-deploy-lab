import type { AddressInfo } from "node:net";

import { createLogger } from "../src/logger.js";
import { createApp, type AppState } from "../src/server.js";

export interface Running {
  baseUrl: string;
  state: AppState;
  lines: string[];
  close(): Promise<void>;
}

// Starts the app on a random local port and captures its log lines.
export async function start(): Promise<Running> {
  const lines: string[] = [];
  const state: AppState = { version: "test", draining: false };
  const server = createApp(state, createLogger("info", (line) => lines.push(line)));
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as AddressInfo;
  return {
    baseUrl: `http://127.0.0.1:${port}`,
    state,
    lines,
    close: () =>
      new Promise<void>((resolve, reject) => {
        server.closeAllConnections();
        server.close((err) => (err ? reject(err) : resolve()));
      }),
  };
}
