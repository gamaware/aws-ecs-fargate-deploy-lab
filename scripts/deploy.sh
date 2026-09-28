#!/usr/bin/env bash
# Deploy one digest-pinned image to the ECS service.
#
# 1. terraform apply on infra/terraform/service with the new image, which
#    registers a task definition revision.
# 2. rolling strategy: Terraform updates the service and waits for a steady
#    state; the circuit breaker and deployment alarms roll back a bad release.
#    codedeploy strategy: start a CodeDeploy blue/green deployment of that
#    revision and wait for it; CodeDeploy rolls back on failure or alarm.
# 3. scripts/verify-deployment.sh checks what is actually serving over HTTPS.
#    With an internal load balancer (private_only, as in make test-live),
#    scripts/verify-deployment-private.sh checks it through the ECS and ELB
#    APIs instead and sends no request to the service.
#
# Usage: scripts/deploy.sh <account>.dkr.ecr.<region>.amazonaws.com/<repo>@sha256:<digest> <app-version>
# Env:   TF_BACKEND_CONFIG  path to a backend config file for terraform init (optional)
#        TF_VAR_FILE        path to a .tfvars file (optional)
#        TF_SERVICE_DIR     service root module to use (default infra/terraform/service)
set -euo pipefail

IMAGE="${1:?usage: deploy.sh <image@sha256:digest> <app-version>}"
APP_VERSION="${2:?usage: deploy.sh <image@sha256:digest> <app-version>}"
TF_DIR="${TF_SERVICE_DIR:-$(cd "$(dirname "$0")/../infra/terraform/service" && pwd)}"

if [[ ! "$IMAGE" =~ @sha256:[0-9a-f]{64}$ ]]; then
  echo "refusing to deploy '$IMAGE': the image must be pinned by digest" >&2
  exit 1
fi

init_args=(-input=false)
if [ "${TF_BACKEND_CONFIG:-}" != "" ]; then
  init_args+=("-backend-config=$TF_BACKEND_CONFIG")
fi
apply_args=(-input=false -auto-approve -var "image=$IMAGE" -var "app_version=$APP_VERSION")
if [ "${TF_VAR_FILE:-}" != "" ]; then
  apply_args+=("-var-file=$TF_VAR_FILE")
fi

terraform -chdir="$TF_DIR" init "${init_args[@]}"
terraform -chdir="$TF_DIR" apply "${apply_args[@]}"

out() {
  terraform -chdir="$TF_DIR" output -raw "$1"
}

strategy="$(out deployment_strategy)"
task_definition="$(out task_definition_arn)"

if [ "$strategy" = "codedeploy" ]; then
  appspec="$(jq --compact-output --null-input \
    --arg td "$task_definition" \
    --arg name "$(out container_name)" \
    --argjson port "$(out container_port)" \
    '{version: 0.0, Resources: [{TargetService: {Type: "AWS::ECS::Service", Properties: {
      TaskDefinition: $td, LoadBalancerInfo: {ContainerName: $name, ContainerPort: $port}}}}]}')"
  revision="$(jq --compact-output --null-input --arg content "$appspec" \
    '{revisionType: "AppSpecContent", appSpecContent: {content: $content}}')"

  deployment_id="$(aws deploy create-deployment \
    --application-name "$(out codedeploy_app_name)" \
    --deployment-group-name "$(out codedeploy_deployment_group_name)" \
    --revision "$revision" \
    --description "harbor-stock-api $APP_VERSION" \
    --query deploymentId --output text)"
  echo "CodeDeploy deployment $deployment_id started"
  # Poll instead of `aws deploy wait`, which gives up after 30 minutes: the
  # canary, the 15-minute wait before old tasks stop and task start-up come close.
  status=""
  for ((i = 0; i < 180; i++)); do
    status="$(aws deploy get-deployment --deployment-id "$deployment_id" \
      --query deploymentInfo.status --output text)"
    case "$status" in
      Succeeded) break ;;
      Failed | Stopped)
        echo "CodeDeploy deployment $deployment_id ended as $status (rolled back)" >&2
        exit 1
        ;;
    esac
    sleep 15
  done
  if [ "$status" != "Succeeded" ]; then
    echo "CodeDeploy deployment $deployment_id still $status after 45 minutes" >&2
    exit 1
  fi
fi

if [ "$(out alb_internal)" = "true" ]; then
  "$(dirname "$0")/verify-deployment-private.sh" \
    "$(out cluster_name)" "$(out service_name)" "$task_definition" "$(out alb_arn)" "$APP_VERSION"
else
  "$(dirname "$0")/verify-deployment.sh" \
    "$(out cluster_name)" "$(out service_name)" "$task_definition" "$(out alb_dns_name)" "$APP_VERSION"
fi
