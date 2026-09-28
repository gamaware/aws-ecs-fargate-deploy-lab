// Twelve-factor settings: everything the container needs comes from the
// environment, so the same image runs locally, in CI and on Fargate.

export type LogLevel = "debug" | "info" | "warn" | "error";

export interface Config {
  port: number;
  version: string;
  logLevel: LogLevel;
  // Seconds to keep serving after SIGTERM while the load balancer drains.
  shutdownGraceSeconds: number;
}

const LOG_LEVELS: readonly LogLevel[] = ["debug", "info", "warn", "error"];

function parseInteger(name: string, raw: string, min: number, max: number): number {
  if (!/^\d+$/.test(raw)) {
    throw new Error(`${name} must be an integer, got "${raw}"`);
  }
  const value = Number(raw);
  if (value < min || value > max) {
    throw new Error(`${name} must be between ${min} and ${max}, got ${value}`);
  }
  return value;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const logLevel = env.LOG_LEVEL ?? "info";
  if (!LOG_LEVELS.includes(logLevel as LogLevel)) {
    throw new Error(`LOG_LEVEL must be one of ${LOG_LEVELS.join(", ")}, got "${logLevel}"`);
  }
  return {
    port: parseInteger("PORT", env.PORT ?? "8080", 1, 65535),
    version: env.APP_VERSION ?? "dev",
    logLevel: logLevel as LogLevel,
    shutdownGraceSeconds: parseInteger("SHUTDOWN_GRACE_SECONDS", env.SHUTDOWN_GRACE_SECONDS ?? "10", 0, 110),
  };
}
