# 0002. Separate Terraform stacks for the registry and the service

## Status

Accepted

## Context

The service stack needs an image digest before it can create a task definition, and the image needs a repository
before it can be pushed. In one stack this is a chicken-and-egg problem, commonly solved with `-target` or a
placeholder image. The two parts also change at different rates: the repository almost never changes, the service
changes on every deploy. Destroying or rebuilding the service must not delete the images a rollback depends on.

## Decision

`infra/terraform/registry` holds the ECR repository and its KMS key. `infra/terraform/service` holds the network,
load balancer, WAF, cluster, service, scaling, alarms and the optional CodeDeploy resources. Each has its own state
file (`registry.tfstate`, `service.tfstate`). The order is registry once, then build and push, then service on each
deploy.

## Consequences

- The pipeline deploys by running `terraform apply` on the service stack only, with a small blast radius.
- The service stack does not need the registry's state: the image reference carries the repository, and the
  execution role uses the AWS managed `AmazonECSTaskExecutionRolePolicy` to pull it.
- A shared network for more services would mean splitting `network.tf` into a third stack.

## Compliance

`make tf-verify` validates and tests both stacks independently. `terraform test` in the registry stack asserts
immutable tags, scan on push, KMS encryption and a lifecycle policy that always keeps rollback targets.

## Notes

Alternatives considered:

- One stack with `-target` on the first apply: works, but the first-run procedure lives outside the code.
- A placeholder public image on the first apply: the task definition would briefly run an image the pipeline did not
  build or scan.
- A separate network stack as well: sensible when two or more services share a VPC. With one service it adds a remote
  state lookup and little else.
