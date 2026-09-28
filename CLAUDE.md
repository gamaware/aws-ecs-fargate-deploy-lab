# CLAUDE.md: aws-ecs-fargate-deploy-lab

Portfolio lab: a TypeScript API containerized onto a distroless image and deployed to ECS Fargate with Terraform.
Fictional client "Harbor Goods". Offline verification only; never run anything against AWS from this repo except
`make test-live`, which the maintainer runs by hand.

## Layout

- `app/`: API source (`src/`), tests (`test/`), multi-stage `Dockerfile`. No runtime dependencies.
- `infra/terraform/registry/`: ECR repository and KMS key (own state).
- `infra/terraform/service/`: VPC, ALB, WAF, ECS service, autoscaling, alarms, optional CodeDeploy (own state).
- `scripts/`: `smoke-test.sh`, `deploy.sh`, `verify-deployment.sh`, `verify-deployment-private.sh`, `test-live.sh`,
  `check_private_plan.py` (live-test pre-flight). `tests/`: its unit tests.
- `docs/adr/`: decisions (FoSA2 format with Compliance). `docs/diagrams/`: `.drawio` sources plus SVG and PNG.

## Commands

- `make verify`: everything CI runs (app tests, pre-flight unit tests, image build, smoke test, Terraform
  fmt/validate/tflint/test, hadolint, Checkov, Trivy).
- `make test-live`: manual, uses the `dev` profile, tags `purpose=portfolio-test`, destroys on exit. Always
  `private_only = true`, with a plan pre-flight; never add an internet-facing resource to the live path (ADR 0008).

## Rules

- Conventional commits on a feature branch; never commit to `main`. No AI attribution anywhere.
- Images are referenced by digest only. Base images in the Dockerfile stay digest-pinned.
- Every Checkov or Trivy skip sits next to the resource with its reason. No blanket skips.
- New Terraform behavior gets an assertion in `tests/*.tftest.hcl` (mocked provider only).
- Only AWS documentation example account IDs (`111122223333`) and `example.com`; no real IDs, ARNs, IPs or emails.
- Regenerate `README.md` Terraform tables with terraform-docs (pre-commit does it); do not edit between the markers.
- Diagrams: edit the `.drawio` source, then export SVG and PNG.
