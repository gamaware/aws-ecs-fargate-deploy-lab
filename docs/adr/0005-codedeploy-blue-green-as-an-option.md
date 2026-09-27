# 0005. Blue/green through CodeDeploy as an option

## Status

Accepted

## Context

Some teams want to test the new version before any customer sees it, and to shift traffic gradually with a one-step
rollback. ECS rolling updates cannot do either.

## Decision

Setting `deployment_strategy = "codedeploy"` switches the service to the `CODE_DEPLOY` deployment controller and adds a
green target group, a test listener on port 9443 (reachable only from `test_listener_cidrs`), a CodeDeploy application
and a deployment group. The default configuration is `CodeDeployDefault.ECSCanary10Percent5Minutes`. CodeDeploy rolls
back on failure and when the same two alarms from ADR 0004 fire, and keeps the old tasks for 15 minutes after the
shift. `scripts/deploy.sh` registers the task definition with Terraform, then starts the CodeDeploy deployment with an
AppSpec that names it.

## Consequences

- Under CodeDeploy, Terraform ignores the service's task definition and load balancer after creation, because
  CodeDeploy owns them.
- Request-count autoscaling is left out in this mode. Its metric is tied to one target group, and the live group
  alternates between blue and green. CPU scaling covers both modes.
- The deployment circuit breaker does not apply to CodeDeploy deployments; alarms and CodeDeploy health checks do
  that job.

## Compliance

The Terraform test file `codedeploy.tftest.hcl` asserts the controller, both target groups, the test listener, the
rollback events and the alarm configuration.

## Notes

Alternatives considered:

- ECS built-in blue/green deployments (deployment controller `ECS` with a blue/green strategy, lifecycle hooks and
  an alternate target group). They avoid a second service to operate and are the better default for a
  new service. CodeDeploy stays here because many existing services already use it, and moving them is a common
  request.
- Rolling only: simpler, no test window.
