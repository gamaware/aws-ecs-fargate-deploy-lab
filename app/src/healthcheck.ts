// Container health probe. The distroless runtime image has no shell or curl,
// so the Docker HEALTHCHECK and the ECS container health check run this file
// with the bundled node binary. Exit 0 when /health answers 200.

const port = process.env.PORT ?? "8080";

try {
  const res = await fetch(`http://127.0.0.1:${port}/health`, { signal: AbortSignal.timeout(2000) });
  process.exit(res.status === 200 ? 0 : 1);
} catch {
  process.exit(1);
}
