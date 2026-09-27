// HTTP routing with the Node.js standard library only: no runtime
// dependencies to patch, and a smaller image.

import { randomUUID } from "node:crypto";
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";

import { findProduct, listProducts, SKU_PATTERN } from "./catalog.js";
import type { Logger } from "./logger.js";

export interface AppState {
  version: string;
  // Flipped by the SIGTERM handler; /ready then answers 503 so the target
  // group stops sending new requests while in-flight ones finish.
  draining: boolean;
}

const SECURITY_HEADERS = {
  "Cache-Control": "no-store",
  "Content-Type": "application/json; charset=utf-8",
  "X-Content-Type-Options": "nosniff",
} as const;

const REQUEST_ID = /^[A-Za-z0-9-]{1,64}$/;

function send(res: ServerResponse, status: number, body: unknown, requestId: string): void {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    ...SECURITY_HEADERS,
    "Content-Length": Buffer.byteLength(payload),
    "X-Request-Id": requestId,
  });
  res.end(res.req.method === "HEAD" ? undefined : payload);
}

function route(url: URL, state: AppState): { status: number; body: unknown } {
  const path = url.pathname;
  if (path === "/health") {
    return { status: 200, body: { status: "ok" } };
  }
  if (path === "/ready") {
    return state.draining
      ? { status: 503, body: { status: "draining" } }
      : { status: 200, body: { status: "ready" } };
  }
  if (path === "/") {
    return { status: 200, body: { service: "harbor-stock-api", version: state.version } };
  }
  if (path === "/api/products") {
    const inStock = url.searchParams.get("inStock");
    if (inStock !== null && inStock !== "true" && inStock !== "false") {
      return { status: 400, body: { error: "inStock must be true or false" } };
    }
    return { status: 200, body: { products: listProducts(inStock === "true") } };
  }
  if (path.startsWith("/api/products/")) {
    const sku = path.slice("/api/products/".length);
    if (!SKU_PATTERN.test(sku)) {
      return { status: 400, body: { error: "sku must look like HG-0000" } };
    }
    const product = findProduct(sku);
    return product === undefined
      ? { status: 404, body: { error: "product not found" } }
      : { status: 200, body: product };
  }
  return { status: 404, body: { error: "not found" } };
}

export function createApp(state: AppState, logger: Logger): Server {
  const server = createServer((req: IncomingMessage, res: ServerResponse) => {
    const started = process.hrtime.bigint();
    const incoming = req.headers["x-request-id"];
    const requestId = typeof incoming === "string" && REQUEST_ID.test(incoming) ? incoming : randomUUID();

    let status: number;
    let body: unknown;
    if (req.method !== "GET" && req.method !== "HEAD") {
      res.setHeader("Allow", "GET, HEAD");
      status = 405;
      body = { error: "method not allowed" };
    } else {
      // The base is a fixed placeholder; only the path and query are used.
      ({ status, body } = route(new URL(req.url ?? "/", "http://localhost"), state));
    }
    send(res, status, body, requestId);

    const durationMs = Number(process.hrtime.bigint() - started) / 1e6;
    logger.info("request", {
      requestId,
      method: req.method,
      path: (req.url ?? "/").split("?")[0],
      status,
      durationMs: Math.round(durationMs * 100) / 100,
    });
  });
  // Longer than the ALB idle timeout (60 s), so the load balancer, not the
  // task, closes idle keep-alive connections. Avoids sporadic 502s.
  server.keepAliveTimeout = 65_000;
  server.headersTimeout = 66_000;
  return server;
}
