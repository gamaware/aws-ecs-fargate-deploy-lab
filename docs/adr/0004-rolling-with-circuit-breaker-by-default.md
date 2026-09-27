# 0004. Rolling deployments with the circuit breaker and alarms by default

Status: Accepted

## Context

A bad release fails in one of two ways: its tasks never become healthy (crash on start, failed health check), or they
start and serve errors. A deployment method should roll back both without anyone watching.

## Decision

The default `deployment_strategy = "rolling"` uses the ECS deployment controller with:

- the deployment circuit breaker, `rollback = true`, for tasks that fail to start or to pass health checks;
- ECS deployment alarms on the target 5xx count and the unhealthy host count, `rollback = true`, for tasks that start
  but misbehave;
- `minimum_healthy_percent = 100` and `maximum_percent = 200`, so capacity never drops during a deploy.

The target group checks `/ready`, not `/health`. On SIGTERM the app answers 503 on `/ready` while it drains.

## Alternatives

- Rolling updates without the circuit breaker: a crash-looping release keeps retrying until someone intervenes.
- Blue/green for every deploy: see ADR 0005. It needs a second target group and listener and more moving parts.

## Consequences

- `scripts/verify-deployment.sh` checks that the primary deployment reached `COMPLETED` on the expected task
  definition. A rollback makes the pipeline fail even though Terraform finished.
- Old and new tasks serve traffic side by side for a few minutes, so releases must stay backwards compatible (true for
  this stateless read API).

## Compliance

The Terraform test `circuit_breaker_and_alarms_roll_back_a_bad_release` asserts the circuit breaker, the alarm
rollback and the 100 percent floor.
