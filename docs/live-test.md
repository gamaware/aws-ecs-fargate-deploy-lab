# Live test (manual)

`make test-live` runs `scripts/test-live.sh`: a full deploy to a real AWS account, a check, and a teardown. It never
runs in CI, and nothing it writes is committed.

## What it does

1. Shows `aws sts get-caller-identity --profile dev` and asks for confirmation (`LIVE_YES=1` skips the prompt).
2. Pre-flight: plans the registry stack and the service stack with the live variables and refuses the run if either
   plan has an internet-facing resource (see [Private-only](#private-only)). Nothing exists yet at this point.
3. Imports a one-day self-signed certificate into ACM for the HTTPS listener.
4. Applies the registry stack from the checked plan, builds the ARM64 image, runs the smoke test and the Trivy gate,
   pushes it and reads its digest from ECR.
5. Checks the service plan again with the real digest and certificate, then runs `scripts/deploy.sh` with that digest
   (`LIVE_STRATEGY=rolling` by default, or `codedeploy`). Because the load balancer is internal, `deploy.sh` ends with
   `scripts/verify-deployment-private.sh`, which checks health through the AWS APIs.
6. On exit, including failures and Ctrl-C: destroys the service and registry stacks, deletes the certificate, then
   lists anything still tagged `purpose=portfolio-test` for this run and fails if something is left. KMS keys stay
   pending deletion for 30 days and ECS keeps deregistered task definitions as inactive; both are free and are
   excluded from that list. The tagging API keeps listing deleted VPC endpoints, security group rules and inactive
   ECS clusters, services and tasks for a while, so the script asks each service whether those still exist. If a
   destroy fails (an expired SSO session, for example), the script keeps the Terraform state in its temporary
   directory, prints the path and exits with an error so the destroy can be run again.

All resources carry `purpose=portfolio-test` and a `run` tag. State and temporary files live in a `mktemp` directory
outside the repository and are deleted at the end.

## Prerequisites

- The maintainer's AWS CLI profile named `dev`, which points at a development account used only for tests like this.
  The script prints the account and asks before creating anything.
- Docker with ARM64 support, Terraform, Trivy, `jq`, `openssl`, Python 3 (standard library only).

## Cost

Under USD 0.25 for a 20-minute rolling run: the load balancer, two small Fargate tasks, three interface endpoints in
two Availability Zones, AWS WAF and CloudWatch, all billed by the hour. A `codedeploy` run takes about 40 minutes and
costs about twice as much.

## Private-only

A live run never creates anything reachable from the internet (ADR
[0008](adr/0008-live-tests-run-private-only.md)).

- **Configuration.** `scripts/test-live.sh` always writes `private_only = true` into the service variables. The stack
  then has no internet gateway, no public subnets and no default route; the load balancer is `internal = true` in the
  private subnets; its security group accepts 80 and 443 from the VPC CIDR only (`ingress_cidrs` is ignored); tasks
  run with `assign_public_ip = false` and reach ECR, S3 and CloudWatch Logs through VPC endpoints. The registry stack
  holds only an ECR repository, its lifecycle policy and a KMS key.
- **Pre-flight.** Before any apply, the script runs `terraform plan -out` for each stack with the exact live
  variables, writes `terraform show -json` output to the run's temporary directory and runs
  `python3 scripts/check_private_plan.py` on it. The checker fails on internet gateways, public NAT gateways, default
  routes to a gateway, load balancers that are not internal, security group ingress from `0.0.0.0/0` or `::/0`, ECS
  services or instances with public IP addresses, subnets that map public IPs, Elastic IPs and other public entry
  points.
  It also refuses any Route 53 resource (hosted zones, records, health checks), a public EKS API endpoint and public S3
  or ECR access: an ECR Public repository, an S3 website endpoint, a public bucket ACL, a public access block with any
  setting off, or a bucket or repository policy that allows any principal without a condition.
  Any violation stops the run before anything is created. The service plan is checked twice: with
  placeholders for the image digest and certificate before anything exists, and with the real values before
  `scripts/deploy.sh` applies it.
- **Offline tests.** `make verify` runs `tests/test_check_private_plan.py` (the checker's rules) and
  `infra/terraform/service/tests/live_private.tftest.hcl`, which plans the service stack with the live variables
  against a mocked provider and fails if the load balancer is public, if an internet gateway, default route or public
  subnet exists, if a load balancer ingress rule allows the world, or if tasks get a public IP.
- **Health checks.** `scripts/verify-deployment-private.sh` sends no request to the service. It waits for the ECS
  deployment to complete, confirms the service serves the new task definition with the expected `APP_VERSION`, that
  the running count equals the desired count with nothing pending, that every task passes its container health check,
  and that every target behind the HTTPS listener is healthy in `aws elbv2 describe-target-health` (the load balancer
  probes `/ready` from inside the VPC).
- **Not covered.** The image build and push use the maintainer's connection to the public ECR endpoint; that is not a
  workload resource. Whether the public listener answers from the internet is not tested live; the mocked tests
  assert the listener configuration, and `scripts/verify-deployment.sh` checks a public deployment over HTTPS.
