# 0007. ARM64 (Graviton) tasks

Status: Accepted

## Context

Fargate bills ARM64 tasks at about 20 percent less than X86_64 for the same vCPU and memory. The app is pure
JavaScript on Node.js, which runs the same on both.

## Decision

The task definition sets `cpu_architecture = "ARM64"` by default. CI builds and smoke-tests the image on an ARM64
runner (`ubuntu-24.04-arm`), so the tested binary matches the one that runs.

## Alternatives

- X86_64: no cost saving; needed only if the app gains a native dependency without ARM64 builds.
- Multi-architecture images: useful for images shared across teams, but doubles build time for one target.

## Consequences

- Local builds on Apple silicon produce the same architecture as production.
- Switching back is one variable (`cpu_architecture = "X86_64"`) plus building on an x86 runner.

## Compliance

The Terraform test `tasks_are_private_and_locked_down` asserts ARM64. The `app` job in `ci.yml` and the `build`
job in `deploy.yml` run on `ubuntu-24.04-arm`.
