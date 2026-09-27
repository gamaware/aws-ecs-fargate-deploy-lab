# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `harbor-stock-api`: TypeScript API on the Node.js standard library with liveness and readiness endpoints, JSON
  logs and graceful SIGTERM draining, with unit tests and a process-level shutdown test.
- Multi-stage Dockerfile onto a distroless, non-root Node.js runtime, both bases pinned by digest.
- Local smoke test that runs the image with the ECS task constraints.
- Terraform registry stack (ECR with immutable tags, scan on push, KMS, lifecycle policy).
- Terraform service stack: VPC with private subnets and VPC endpoints, HTTPS load balancer with access logs, AWS WAF,
  ECS Fargate on ARM64, deployment circuit breaker and alarm rollback, CPU and request autoscaling, alarms,
  dashboard, and optional CodeDeploy blue/green.
- Mocked `terraform test` suites for both stacks.
- CI (`make verify` jobs), deploy workflow (build once, scan, push by digest, deploy), OpenSSF Scorecard.
- Seven ADRs, runbook, live-test guide and diagrams.

### Security

- TODO: re-pin the `gamaware/.github` reusable workflows in `.github/workflows/ci.yml` from `@main` to a reviewed
  commit SHA, then drop the `gamaware/*` exception in `zizmor.yml`.
