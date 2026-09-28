# 0008. Live tests run private-only

## Status

Accepted

## Context

`make test-live` deploys both stacks to a real account to prove what the mocked tests cannot: IAM permissions,
quotas and a steady ECS service. The production configuration puts the load balancer in public subnets behind an
internet gateway and accepts HTTPS from `0.0.0.0/0`, because that is the service's entry point. A test run does not
need any of that, and a disposable environment reachable from the internet is exposed for as long as the run lasts or
longer if a teardown fails.

## Decision

A live run never creates anything reachable from the internet.

- The service stack has a `private_only` variable. `scripts/test-live.sh` always sets it to `true`, which removes
  the internet gateway, the public subnets, the public route table and its default route, puts the load balancer in
  the private subnets with `internal = true`, and replaces `ingress_cidrs` with the VPC CIDR. Tasks keep
  `assign_public_ip = false` and reach ECR, S3 and CloudWatch Logs through the VPC endpoints (ADR 0003).
  `test_listener_cidrs` rejects `0.0.0.0/0` when `private_only` is `true`.
- The live test creates no Route 53 resource; the pre-flight checker refuses any, and also refuses public S3, ECR,
  EKS or API endpoints.
- Before anything is created, the script plans the registry stack and the service stack with the live variables
  (placeholders of the same shape for the image digest and certificate, which do not exist yet), writes
  `terraform show -json` output to the run's temporary directory, and runs `scripts/check_private_plan.py` on it.
  Any internet-facing resource stops the run. The registry is applied from the checked plan file; the service plan is
  checked again with the real image and certificate before `scripts/deploy.sh` applies it.
- Health is checked through the ECS and Elastic Load Balancing APIs (`scripts/verify-deployment-private.sh`): the
  deployment completed, the service serves the expected task definition and `APP_VERSION`, the running count equals
  the desired count, every task passes its container health check, and every target behind the HTTPS listener is
  healthy. The load balancer probes `/ready` from inside the VPC. No request goes to the service over the internet.
- The production default stays `private_only = false`, with the public load balancer.

## Consequences

- A failed teardown leaves only private resources behind.
- The live test no longer proves that the public listener answers over the internet; the HTTPS listener, TLS policy
  and redirect are still asserted by the mocked tests, and `scripts/verify-deployment.sh` remains the check for a
  public deployment.
- The pre-flight needs Python 3 on the maintainer's machine (standard library only).
- Building and pushing the image still uses the maintainer's connection to the public ECR endpoint; that is not a
  workload resource.

## Compliance

- `infra/terraform/service/tests/live_private.tftest.hcl` (mocked provider, part of `make verify`) plans the stack with
  the live variables for both deployment strategies and fails if the load balancer is not internal, if an internet
  gateway, default route or public subnet exists, if a subnet maps public IP addresses, if any load balancer ingress
  rule allows `0.0.0.0/0` or `::/0`, or if tasks get a public IP.
- `tests/test_check_private_plan.py` (part of `make verify`) covers the pre-flight checker.
- `scripts/test-live.sh` exits before any apply when `scripts/check_private_plan.py` reports a violation.

## Notes

Alternatives considered:

- A separate live-only root module: a second copy of the network and load balancer that can drift from the production
  stack.
- Keeping the public load balancer and restricting ingress to the maintainer's IP: still an internet-facing resource,
  and the address changes between runs.
