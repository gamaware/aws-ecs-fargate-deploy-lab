#!/usr/bin/env bash
# Post-deploy check for an internal load balancer (private_only = true, as in
# make test-live). Nothing here sends a request to the service: every check
# goes through the ECS and Elastic Load Balancing APIs.
#
#   - the deployment completed (a circuit-breaker rollback leaves it FAILED);
#   - the service serves the expected task definition, whose APP_VERSION is
#     the expected version;
#   - the running count reached the desired count with nothing pending;
#   - every running task passes its container health check;
#   - the HTTPS listener's target group reports every task healthy (the load
#     balancer probes /ready from inside the VPC).
#
# Usage: scripts/verify-deployment-private.sh <cluster> <service> <task-definition-arn> <alb-arn> <app-version>
set -euo pipefail

CLUSTER="$1"
SERVICE="$2"
EXPECTED_TD="$3"
ALB_ARN="$4"
EXPECTED_VERSION="$5"

service_query() {
  aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --query "services[0].$1" --output text
}

# With deployment alarms, ECS keeps a rolling deployment IN_PROGRESS for a
# bake period after the tasks are steady. Wait up to 15 minutes for it.
for ((i = 0; i < 90; i++)); do
  rollout_state="$(service_query "deployments[?status=='PRIMARY'] | [0].rolloutState")"
  [ "$rollout_state" = "IN_PROGRESS" ] || break
  sleep 10
done

# Under CodeDeploy the service keeps the task set model and reports no
# rolloutState; the CodeDeploy wait in deploy.sh already proved success.
if [ "$rollout_state" = "None" ]; then
  served_td="$(service_query "taskSets[?status=='PRIMARY'] | [0].taskDefinition")"
elif [ "$rollout_state" = "COMPLETED" ]; then
  served_td="$(service_query "taskDefinition")"
else
  echo "FAIL: primary deployment is $rollout_state (the circuit breaker may have rolled back)" >&2
  exit 1
fi
if [ "$served_td" != "$EXPECTED_TD" ]; then
  echo "FAIL: service serves $served_td, expected $EXPECTED_TD (rolled back?)" >&2
  exit 1
fi
echo "ok   ECS deployment ${rollout_state/None/managed by CodeDeploy} serves $served_td"

version="$(aws ecs describe-task-definition --task-definition "$EXPECTED_TD" \
  --query "taskDefinition.containerDefinitions[0].environment[?name=='APP_VERSION'] | [0].value" --output text)"
if [ "$version" != "$EXPECTED_VERSION" ]; then
  echo "FAIL: task definition sets APP_VERSION '$version', expected '$EXPECTED_VERSION'" >&2
  exit 1
fi
echo "ok   task definition sets APP_VERSION $version"

# Steady state: every desired task running, none pending. Up to 5 minutes.
steady=0
for ((i = 0; i < 30; i++)); do
  read -r desired running pending < <(service_query "[desiredCount, runningCount, pendingCount]")
  if [ "$desired" -gt 0 ] && [ "$running" = "$desired" ] && [ "$pending" = "0" ]; then
    steady=1
    break
  fi
  sleep 10
done
if [ "$steady" != "1" ]; then
  echo "FAIL: service runs $running of $desired tasks ($pending pending)" >&2
  exit 1
fi
echo "ok   $running of $desired tasks running, none pending"

# Container health checks of the running tasks. Up to 3 minutes.
unhealthy=""
for ((i = 0; i < 18; i++)); do
  task_list="$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE" \
    --desired-status RUNNING --query 'taskArns[]' --output text)"
  read -r -a tasks <<< "${task_list/None/}"
  if [ "${#tasks[@]}" -gt 0 ]; then
    unhealthy="$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "${tasks[@]}" \
      --query "tasks[?healthStatus!='HEALTHY' || taskDefinitionArn!='$EXPECTED_TD'].taskArn" --output text)"
    [ "$unhealthy" = "" ] && break
  else
    unhealthy="no running tasks"
  fi
  sleep 10
done
if [ "$unhealthy" != "" ]; then
  echo "FAIL: tasks not HEALTHY on $EXPECTED_TD: $unhealthy" >&2
  exit 1
fi
echo "ok   ${#tasks[@]} tasks pass the container health check"

# Target health behind the HTTPS listener. Under CodeDeploy the listener
# forwards to whichever target group the last deployment shifted traffic to.
target_group="$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" \
  --query "Listeners[?Port==\`443\`] | [0].DefaultActions[0].[TargetGroupArn, ForwardConfig.TargetGroups[?Weight>\`0\`] | [0].TargetGroupArn] | [?@ != \`null\`] | [0]" \
  --output text)"
if [ "$target_group" = "" ] || [ "$target_group" = "None" ]; then
  echo "FAIL: no target group behind the HTTPS listener of $ALB_ARN" >&2
  exit 1
fi
healthy=0
for ((i = 0; i < 18; i++)); do
  read -r healthy total < <(aws elbv2 describe-target-health --target-group-arn "$target_group" \
    --query "[length(TargetHealthDescriptions[?TargetHealth.State=='healthy']), length(TargetHealthDescriptions)]" \
    --output text)
  [ "$healthy" -ge "$desired" ] && [ "$healthy" = "$total" ] && break
  sleep 10
done
if [ "$healthy" -lt "$desired" ] || [ "$healthy" != "$total" ]; then
  echo "FAIL: $healthy of $total targets healthy in $target_group, expected $desired" >&2
  exit 1
fi
echo "ok   $healthy of $total targets healthy behind the HTTPS listener"
