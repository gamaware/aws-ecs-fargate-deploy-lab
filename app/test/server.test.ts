import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

import { start, type Running } from "./helpers.js";

describe("HTTP API", () => {
  let app: Running;

  before(async () => {
    app = await start();
  });

  after(async () => {
    await app.close();
  });

  it("answers /health with 200 and JSON", async () => {
    const res = await fetch(`${app.baseUrl}/health`);
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("content-type"), "application/json; charset=utf-8");
    assert.deepEqual(await res.json(), { status: "ok" });
  });

  it("reports the version on /", async () => {
    const res = await fetch(`${app.baseUrl}/`);
    assert.deepEqual(await res.json(), { service: "harbor-stock-api", version: "test" });
  });

  it("lists products and filters by stock", async () => {
    const all = (await (await fetch(`${app.baseUrl}/api/products`)).json()) as { products: unknown[] };
    const inStock = (await (await fetch(`${app.baseUrl}/api/products?inStock=true`)).json()) as {
      products: { stock: number }[];
    };
    assert.equal(all.products.length, 4);
    assert.equal(inStock.products.length, 3);
    assert.ok(inStock.products.every((p) => p.stock > 0));
  });

  it("rejects an invalid inStock filter", async () => {
    const res = await fetch(`${app.baseUrl}/api/products?inStock=yes`);
    assert.equal(res.status, 400);
  });

  it("returns one product by SKU", async () => {
    const res = await fetch(`${app.baseUrl}/api/products/HG-1002`);
    assert.equal(res.status, 200);
    assert.equal(((await res.json()) as { name: string }).name, "Enamel camp mug");
  });

  it("returns 404 for an unknown SKU and 400 for a malformed one", async () => {
    assert.equal((await fetch(`${app.baseUrl}/api/products/HG-9999`)).status, 404);
    assert.equal((await fetch(`${app.baseUrl}/api/products/..%2Fetc`)).status, 400);
  });

  it("returns 404 for unknown paths", async () => {
    assert.equal((await fetch(`${app.baseUrl}/admin`)).status, 404);
  });

  it("allows only GET and HEAD", async () => {
    const res = await fetch(`${app.baseUrl}/api/products`, { method: "POST", body: "{}" });
    assert.equal(res.status, 405);
    assert.equal(res.headers.get("allow"), "GET, HEAD");
    const head = await fetch(`${app.baseUrl}/health`, { method: "HEAD" });
    assert.equal(head.status, 200);
    assert.equal(await head.text(), "");
  });

  it("sets security headers", async () => {
    const res = await fetch(`${app.baseUrl}/health`);
    assert.equal(res.headers.get("x-content-type-options"), "nosniff");
    assert.equal(res.headers.get("cache-control"), "no-store");
  });

  it("echoes a well-formed request ID and replaces a malformed one", async () => {
    const good = await fetch(`${app.baseUrl}/health`, { headers: { "X-Request-Id": "abc-123" } });
    assert.equal(good.headers.get("x-request-id"), "abc-123");
    const bad = await fetch(`${app.baseUrl}/health`, { headers: { "X-Request-Id": "a b<script>" } });
    assert.match(bad.headers.get("x-request-id") ?? "", /^[0-9a-f-]{36}$/);
  });

  it("logs one JSON line per request without the query string", async () => {
    app.lines.length = 0;
    await fetch(`${app.baseUrl}/api/products?inStock=true`);
    assert.equal(app.lines.length, 1);
    const entry = JSON.parse(app.lines[0] ?? "") as Record<string, unknown>;
    assert.equal(entry.msg, "request");
    assert.equal(entry.path, "/api/products");
    assert.equal(entry.status, 200);
    assert.equal(typeof entry.durationMs, "number");
  });

  it("answers /ready with 503 while draining", async () => {
    assert.equal((await fetch(`${app.baseUrl}/ready`)).status, 200);
    app.state.draining = true;
    try {
      const res = await fetch(`${app.baseUrl}/ready`);
      assert.equal(res.status, 503);
      // Liveness stays green: a draining task is healthy, just not taking traffic.
      assert.equal((await fetch(`${app.baseUrl}/health`)).status, 200);
    } finally {
      app.state.draining = false;
    }
  });
});
