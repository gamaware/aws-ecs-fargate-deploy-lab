// One JSON object per line on stdout. The awslogs driver ships each line to
// CloudWatch Logs, where Logs Insights can query the fields directly.

import type { LogLevel } from "./config.js";

const RANK: Record<LogLevel, number> = { debug: 10, info: 20, warn: 30, error: 40 };

export type Fields = Record<string, string | number | boolean | undefined>;

export interface Logger {
  debug(msg: string, fields?: Fields): void;
  info(msg: string, fields?: Fields): void;
  warn(msg: string, fields?: Fields): void;
  error(msg: string, fields?: Fields): void;
}

export function createLogger(level: LogLevel, write: (line: string) => void = (line) => {
  process.stdout.write(`${line}\n`);
}): Logger {
  const log = (at: LogLevel, msg: string, fields: Fields = {}): void => {
    if (RANK[at] < RANK[level]) {
      return;
    }
    write(JSON.stringify({ time: new Date().toISOString(), level: at, msg, ...fields }));
  };
  return {
    debug: (msg, fields) => log("debug", msg, fields),
    info: (msg, fields) => log("info", msg, fields),
    warn: (msg, fields) => log("warn", msg, fields),
    error: (msg, fields) => log("error", msg, fields),
  };
}
