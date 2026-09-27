# 0001. Multi-stage build onto a distroless Node.js runtime

## Status

Accepted

## Context

The API is written in TypeScript. Running it needs Node.js and the compiled JavaScript, nothing else. The compiler,
the type definitions, the tests and npm itself are build-time tools. Every package left in the runtime image is one
more thing to scan, patch and explain in a vulnerability report, and a shell in the image makes a compromised
container more useful to an attacker.

## Decision

We build in two stages. The build stage (`node:24-trixie-slim`) runs `npm ci`, compiles, and runs the unit tests, so
an image with failing tests cannot be built. The runtime stage (`gcr.io/distroless/nodejs24-debian13:nonroot`) gets
only `dist/src` and `package.json`. Both base images are pinned by digest, and Dependabot proposes digest updates.
The app has no runtime dependencies, so no `node_modules` is copied.

## Consequences

- No shell in the container. The Docker `HEALTHCHECK` and the ECS container health check run
  `/nodejs/bin/node src/healthcheck.js` instead of `curl`. `aws ecs execute-command` has nothing to attach to; debugging
  relies on logs.
- The image runs as UID 65532 and works with a read-only root filesystem because the app writes nothing to disk.
- The Trivy gate blocks any image with a fixable HIGH or CRITICAL finding.

## Compliance

`make hadolint`, `make smoke` (runs the image read-only, non-root, with all capabilities dropped) and
`make trivy` in CI. The Terraform test `tasks_are_private_and_locked_down` asserts the user and read-only root
filesystem in the task definition.

## Notes

Alternatives considered:

- `node:24-slim` as the runtime: simple, but ships a shell, apt and npm, which Trivy then reports.
- Alpine: small, but musl differs from the glibc the tests ran on.
- Single stage: the compiler and tests end up in production.

The build stage runs the tests a second time after `make app-test`. That costs a few seconds and proves the tests pass
on the exact sources that went into the image.
