# Live test (manual)

`make test-live` runs `scripts/test-live.sh`: a full deploy to a real AWS account, a check, and a teardown. It never
runs in CI, and nothing it writes is committed.

## What it does

1. Shows `aws sts get-caller-identity --profile dev` and asks for confirmation (`LIVE_YES=1` skips the prompt).
2. Imports a one-day self-signed certificate into ACM for the HTTPS listener.
3. Applies the registry stack, builds the ARM64 image, runs the smoke test and the Trivy gate, pushes it and reads
   its digest from ECR.
4. Runs `scripts/deploy.sh` with that digest (`LIVE_STRATEGY=rolling` by default, or `codedeploy`), which ends with
   `scripts/verify-deployment.sh` (TLS verification off for the self-signed certificate only).
5. On exit, including failures and Ctrl-C: destroys the service and registry stacks, deletes the certificate, then
   lists anything still tagged `purpose=portfolio-test` for this run and fails if something is left. KMS keys stay
   pending deletion for 30 days and ECS keeps deregistered task definitions as inactive; both are free and are
   excluded from that list. The tagging API keeps listing deleted VPC endpoints, security group rules and inactive
   ECS clusters, services and tasks for a while, so the script asks each service whether those still exist.

All resources carry `purpose=portfolio-test` and a `run` tag. State and temporary files live in a `mktemp` directory
outside the repository and are deleted at the end.

## Prerequisites

- The maintainer's AWS CLI profile named `dev`, which points at a development account used only for tests like this.
  The script prints the account and asks before creating anything.
- Docker with ARM64 support, Terraform, Trivy, `jq`, `openssl`.

## Cost

Under USD 0.25 for a 20-minute rolling run: the load balancer, two small Fargate tasks, three interface endpoints in
two Availability Zones, AWS WAF and CloudWatch, all billed by the hour. A `codedeploy` run takes about 40 minutes and
costs about twice as much.
