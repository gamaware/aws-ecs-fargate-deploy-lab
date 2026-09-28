#!/usr/bin/env bash
# Local smoke test of the built image under the same constraints the ECS task
# definition sets: read-only root filesystem, non-root user, no Linux
# capabilities, no privilege escalation. Checks the endpoints, the Docker
# health check and a clean exit on SIGTERM (what ECS sends on task stop).
#
# Usage: scripts/smoke-test.sh [image]   (default: harbor-stock-api:local)
set -euo pipefail

IMAGE="${1:-harbor-stock-api:local}"
NAME="harbor-smoke-$$"
PORT="${SMOKE_PORT:-18080}"

cleanup() {
  docker rm --force "$NAME" > /dev/null 2>&1 || true
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  docker logs "$NAME" >&2 || true
  exit 1
}

docker run --detach --name "$NAME" \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --env SHUTDOWN_GRACE_SECONDS=2 \
  --publish "127.0.0.1:$PORT:8080" \
  "$IMAGE" > /dev/null

user="$(docker inspect --format '{{.Config.User}}' "$NAME")"
[ "$user" = "65532:65532" ] || fail "image runs as '$user', expected 65532:65532"

for ((i = 0; i < 30; i++)); do
  if curl --silent --fail "http://127.0.0.1:$PORT/health" > /dev/null; then
    break
  fi
  sleep 0.5
done

body="$(curl --silent --fail "http://127.0.0.1:$PORT/health")" || fail "/health did not answer"
[ "$body" = '{"status":"ok"}' ] || fail "/health returned $body"
echo "ok   /health -> $body"

count="$(curl --silent --fail "http://127.0.0.1:$PORT/api/products" | grep -o '"sku"' | wc -l | tr -d ' ')"
[ "$count" = "4" ] || fail "/api/products returned $count products, expected 4"
echo "ok   /api/products -> $count products"

code="$(curl --silent --output /dev/null --write-out '%{http_code}' "http://127.0.0.1:$PORT/api/products/HG-9999")"
[ "$code" = "404" ] || fail "unknown SKU returned $code, expected 404"
echo "ok   /api/products/HG-9999 -> 404"

for ((i = 0; i < 40; i++)); do
  health="$(docker inspect --format '{{.State.Health.Status}}' "$NAME")"
  [ "$health" = "healthy" ] && break
  sleep 0.5
done
[ "$health" = "healthy" ] || fail "Docker health check is '$health'"
echo "ok   HEALTHCHECK -> healthy"

docker stop --signal SIGTERM --time 15 "$NAME" > /dev/null
exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$NAME")"
[ "$exit_code" = "0" ] || fail "container exited with $exit_code after SIGTERM, expected 0"
docker logs "$NAME" 2> /dev/null | grep -q '"msg":"stopped"' || fail "no clean stop in the logs"
echo "ok   SIGTERM -> drained and exited 0"

echo "smoke test passed for $IMAGE"
