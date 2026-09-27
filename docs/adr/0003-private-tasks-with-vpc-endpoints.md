# 0003. Private tasks with VPC endpoints instead of a NAT gateway

Status: Accepted

## Context

Fargate tasks need to pull their image from ECR and write logs to CloudWatch Logs. The usual way is a NAT gateway,
which also gives the tasks a path to anywhere on the internet. This API calls no external services.

## Decision

Tasks run in private subnets with no default route. They reach AWS through interface endpoints for `ecr.api`,
`ecr.dkr` and `logs`, and the S3 gateway endpoint for image layers. The task security group allows egress only to
the endpoint security group and the S3 prefix list on 443. Tasks get no public IP address.

## Alternatives

- One NAT gateway: about the same monthly cost as three interface endpoints in two Availability Zones, but it opens
  outbound internet access and is a single-zone dependency unless doubled.
- Public subnets with public IPs: cheapest, but every task is directly addressable and egress is open.

## Consequences

- A compromised task cannot reach the internet to download tools or send data out.
- Interface endpoints are billed per hour per Availability Zone. At two zones, three endpoints cost roughly what one
  NAT gateway does before data processing charges.
- If the app later calls a third-party API, add a NAT gateway (or an egress proxy) and record the change in a new ADR.
  If it calls another AWS service, add that service's endpoint.

## Compliance

The task security group has no `0.0.0.0/0` egress rule, and the private route table has no routes (see
`network.tf`). The Terraform test `tasks_are_private_and_locked_down` asserts `assign_public_ip = false`. VPC flow logs
record every attempt.
