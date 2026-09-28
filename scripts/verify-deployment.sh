#!/usr/bin/env bash
# Post-deploy check: the service runs the expected task definition, the
# deployment completed (a circuit-breaker rollback leaves it FAILED), and the
# public endpoint serves the expected version.
#
# Usage: scripts/verify-deployment.sh <cluster> <service> <task-definition-arn> <alb-dns-name> <app-version>
# Env:   VERIFY_INSECURE_TLS=1  accept a self-signed certificate (a test environment with a public load balancer)
#
# make test-live never uses this script: its load balancer is internal, so
# deploy.sh runs scripts/verify-deployment-private.sh instead.
set -euo pipefail

CLUSTER="$1"
SERVICE="$2"
EXPECTED_TD="$3"
ALB_DNS="$4"
EXPECTED_VERSION="$5"

curl_args=(--silent --show-error --fail --max-time 10)
if [ "${VERIFY_INSECURE_TLS:-0}" = "1" ]; then
  curl_args+=(--insecure)
fi

# With deployment alarms, ECS keeps a rolling deployment IN_PROGRESS for a
# bake period after the tasks are steady. Wait up to 15 minutes for it.
for ((i = 0; i < 90; i++)); do
  read -r primary_td rollout_state < <(aws ecs describe-services \
    --cluster "$CLUSTER" --services "$SERVICE" \
    --query "services[0].[taskDefinition, deployments[?status=='PRIMARY'] | [0].rolloutState]" \
    --output text)
  [ "$rollout_state" = "IN_PROGRESS" ] || break
  sleep 10
done

# Under CodeDeploy the service keeps the task set model and reports no
# rolloutState; the CodeDeploy wait already proved success.
if [ "$rollout_state" != "None" ] && [ "$rollout_state" != "COMPLETED" ]; then
  echo "FAIL: primary deployment is $rollout_state (the circuit breaker may have rolled back)" >&2
  exit 1
fi
if [ "$rollout_state" = "COMPLETED" ] && [ "$primary_td" != "$EXPECTED_TD" ]; then
  echo "FAIL: service runs $primary_td, expected $EXPECTED_TD (rolled back?)" >&2
  exit 1
fi
echo "ok   ECS deployment ${rollout_state/None/managed by CodeDeploy}"

body=""
for ((i = 0; i < 12; i++)); do
  if body="$(curl "${curl_args[@]}" "https://$ALB_DNS/")"; then
    break
  fi
  sleep 5
done
version="$(jq --raw-output '.version // "none"' <<< "${body:-null}")"
if [ "$version" != "$EXPECTED_VERSION" ]; then
  echo "FAIL: https://$ALB_DNS/ reports version '$version', expected '$EXPECTED_VERSION'" >&2
  exit 1
fi
echo "ok   https://$ALB_DNS/ serves version $version"

curl "${curl_args[@]}" "https://$ALB_DNS/health" > /dev/null
echo "ok   https://$ALB_DNS/health"
