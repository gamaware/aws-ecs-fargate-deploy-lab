#!/usr/bin/env bash
# Manual end-to-end test against a real AWS account (make test-live).
# Never runs in CI. Uses the maintainer's "dev" profile only, tags every
# resource purpose=portfolio-test, destroys everything on exit (success,
# failure or Ctrl-C) and then checks that nothing tagged is left.
#
# Private-only: the service stack runs with private_only = true (internal load
# balancer, no internet gateway, public subnets or default route, ingress from
# the VPC CIDR only, tasks without public IPs). Before anything is created,
# both stacks are planned with the live variables and
# scripts/check_private_plan.py refuses the run if either plan has an
# internet-facing resource. Health is checked through the ECS and ELB APIs
# (scripts/verify-deployment-private.sh), never over the internet.
# See docs/adr/0008-live-tests-run-private-only.md.
#
# Cost: under USD 0.25 for a 20-minute run (ALB, 2 Fargate tasks, 3 interface
# endpoints x 2 AZs, WAF, all billed hourly; KMS keys pending deletion are free).
#
# Env: LIVE_STRATEGY=rolling|codedeploy (default rolling)
#      LIVE_REGION (default us-east-1)
#      LIVE_YES=1 skips the confirmation prompt
# Output goes to a temporary directory outside the repository.
set -euo pipefail

PROFILE="dev"
REGION="${LIVE_REGION:-us-east-1}"
STRATEGY="${LIVE_STRATEGY:-rolling}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN_ID="$(date +%s | tail -c 7)"
NAME="harbor-test-$RUN_ID"
WORK="$(mktemp -d)"
TAG_KEY="purpose"
TAG_VALUE="portfolio-test"

aws_cli() {
  aws --profile "$PROFILE" --region "$REGION" "$@"
}

echo "Account for this run (profile $PROFILE):"
aws sts get-caller-identity --profile "$PROFILE" --output table
ACCOUNT_ID="$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)"
if [ "${LIVE_YES:-0}" != "1" ]; then
  read -r -p "Create and destroy $NAME ($STRATEGY) in $REGION on this account? [y/N] " answer
  [ "$answer" = "y" ] || exit 1
fi

# Terraform reads the profile from the environment; scoped to this script.
export AWS_PROFILE="$PROFILE"
export AWS_REGION="$REGION"
export TF_IN_AUTOMATION=1

cp -R "$REPO_ROOT/infra/terraform" "$WORK/terraform"
rm -rf "$WORK"/terraform/*/.terraform "$WORK"/terraform/*/terraform.tfstate*
REGISTRY="$WORK/terraform/registry"
SERVICE="$WORK/terraform/service"
TAGS="{\"$TAG_KEY\"=\"$TAG_VALUE\",\"run\"=\"$RUN_ID\"}"
REGISTRY_VARS=(-var "name=$NAME" -var force_delete=true -var "tags=$TAGS")
CERT_ARN=""

# The tagging API keeps deleted resources listed for a while (VPC endpoints,
# INACTIVE ECS clusters and services), so ask each service whether the ARN
# still exists. Unknown types count as present.
still_exists() {
  local arn="$1" id="${1##*/}"
  case "$arn" in
    *:ecs:*:cluster/*)
      [ "$(aws_cli ecs describe-clusters --clusters "$arn" \
        --query "clusters[?status!='INACTIVE'] | length(@)" --output text)" != "0" ] ;;
    *:ecs:*:service/*)
      [ "$(aws_cli ecs describe-services --cluster "$(cut -d/ -f2 <<< "$arn")" --services "$arn" \
        --query "services[?status!='INACTIVE'] | length(@)" --output text)" != "0" ] ;;
    *:ecs:*:task/*)
      [ "$(aws_cli ecs describe-tasks --cluster "$(cut -d/ -f2 <<< "$arn")" --tasks "$arn" \
        --query "tasks[?lastStatus!='STOPPED'] | length(@)" --output text)" != "0" ] ;;
    *:vpc-endpoint/*)
      [ "$(aws_cli ec2 describe-vpc-endpoints --filters "Name=vpc-endpoint-id,Values=$id" \
        --query "VpcEndpoints[?State!='deleted'] | length(@)" --output text)" != "0" ] ;;
    *:security-group/*)
      [ "$(aws_cli ec2 describe-security-groups --filters "Name=group-id,Values=$id" \
        --query 'length(SecurityGroups)' --output text)" != "0" ] ;;
    *:security-group-rule/*)
      [ "$(aws_cli ec2 describe-security-group-rules --filters "Name=security-group-rule-id,Values=$id" \
        --query 'length(SecurityGroupRules)' --output text)" != "0" ] ;;
    *) true ;;
  esac
}

teardown() {
  set +e
  echo "--- teardown"
  destroyed=1
  if [ -f "$SERVICE/terraform.tfstate" ]; then
    terraform -chdir="$SERVICE" destroy -input=false -auto-approve -var-file="$WORK/service.tfvars" || destroyed=0
  fi
  if [ -f "$REGISTRY/terraform.tfstate" ]; then
    terraform -chdir="$REGISTRY" destroy -input=false -auto-approve "${REGISTRY_VARS[@]}" || destroyed=0
  fi
  if [ "$CERT_ARN" != "" ]; then
    aws_cli acm delete-certificate --certificate-arn "$CERT_ARN" || destroyed=0
  fi
  if [ "$destroyed" = "0" ]; then
    # Keep the state so the destroy can be retried (for example after an
    # expired SSO session): terraform -chdir=<dir> destroy -var-file=...
    echo "FAIL: teardown did not complete; state kept in $WORK/terraform, rerun its destroy" >&2
    exit 1
  fi

  echo "--- leftovers tagged $TAG_KEY=$TAG_VALUE, run=$RUN_ID"
  leftovers=""
  for ((i = 0; i < 6; i++)); do
    if ! arns="$(aws_cli resourcegroupstaggingapi get-resources \
      --tag-filters "Key=$TAG_KEY,Values=$TAG_VALUE" "Key=run,Values=$RUN_ID" \
      --query 'ResourceTagMappingList[].ResourceARN' --output text)"; then
      echo "FAIL: cannot list tagged resources; check tag run=$RUN_ID by hand" >&2
      exit 1
    fi
    leftovers=""
    while read -r arn; do
      if still_exists "$arn"; then
        leftovers+="$arn"$'\n'
      fi
    done < <(tr '\t' '\n' <<< "$arns" | sort -u | grep -v -e '^$' -e '^None$' -e ':kms:' -e ':task-definition/')
    [ "$leftovers" = "" ] && break
    sleep 20
  done
  rm -rf "$WORK"
  if [ "$leftovers" != "" ]; then
    echo "FAIL: resources left behind, delete them by hand:" >&2
    echo "$leftovers" >&2
    exit 1
  fi
  echo "nothing left (KMS keys stay pending deletion for 30 days at no cost; ECS keeps"
  echo "deregistered task definitions as INACTIVE, which cost nothing)"
}
trap teardown EXIT

# The live service configuration. private_only = true is what keeps the run
# off the internet; the pre-flight below refuses the run if it is missing.
write_service_tfvars() {
  cat > "$WORK/service.tfvars" <<TFVARS
name                = "$NAME"
region              = "$REGION"
certificate_arn     = "$1"
deployment_strategy = "$STRATEGY"
deletion_protection = false
log_retention_days  = 1
image               = "$2"
app_version         = "$RUN_ID"
tags                = $TAGS
private_only        = true
TFVARS
}

# Plan a stack with the live variables and refuse the run if the plan has
# anything internet-facing. Plan and JSON stay in the run's temporary directory.
preflight() {
  local dir="$1" label="$2"
  shift 2
  echo "--- pre-flight: $label plan must be private-only"
  terraform -chdir="$dir" plan -input=false -out="$WORK/$label.tfplan" "$@" > /dev/null
  terraform -chdir="$dir" show -json "$WORK/$label.tfplan" > "$WORK/$label-plan.json"
  if ! python3 "$REPO_ROOT/scripts/check_private_plan.py" "$WORK/$label-plan.json"; then
    echo "FAIL: the $label plan is not private-only; nothing was applied" >&2
    exit 1
  fi
}

# Before anything exists: plan both stacks. The image and certificate do not
# exist yet, so the service plan uses placeholders of the same shape; they do
# not change the network, load balancer or security groups.
terraform -chdir="$REGISTRY" init -input=false > /dev/null
terraform -chdir="$SERVICE" init -input=false > /dev/null
preflight "$REGISTRY" registry "${REGISTRY_VARS[@]}"
write_service_tfvars \
  "arn:aws:acm:$REGION:$ACCOUNT_ID:certificate/00000000-0000-0000-0000-000000000000" \
  "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$NAME@sha256:$(printf '0%.0s' {1..64})"
preflight "$SERVICE" service-placeholder -var-file="$WORK/service.tfvars"

echo "--- self-signed certificate for the HTTPS listener"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj "/CN=$NAME.example.com" \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2> /dev/null
CERT_ARN="$(aws_cli acm import-certificate \
  --certificate "fileb://$WORK/cert.pem" --private-key "fileb://$WORK/key.pem" \
  --tags "Key=$TAG_KEY,Value=$TAG_VALUE" "Key=run,Value=$RUN_ID" \
  --query CertificateArn --output text)"

echo "--- registry (the plan checked above)"
terraform -chdir="$REGISTRY" apply -input=false "$WORK/registry.tfplan"
REPO_URL="$(terraform -chdir="$REGISTRY" output -raw repository_url)"

echo "--- build once, scan, push"
docker build --platform linux/arm64 --build-arg "APP_VERSION=$RUN_ID" --tag "$REPO_URL:$RUN_ID" "$REPO_ROOT/app"
"$REPO_ROOT/scripts/smoke-test.sh" "$REPO_URL:$RUN_ID"
trivy image --quiet --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 "$REPO_URL:$RUN_ID"
aws_cli ecr get-login-password | docker login --username AWS --password-stdin "${REPO_URL%%/*}"
docker push "$REPO_URL:$RUN_ID" > /dev/null
DIGEST="$(aws_cli ecr describe-images --repository-name "$NAME" --image-ids "imageTag=$RUN_ID" \
  --query 'imageDetails[0].imageDigest' --output text)"
IMAGE="$REPO_URL@$DIGEST"
echo "pushed $IMAGE"

echo "--- service ($STRATEGY)"
write_service_tfvars "$CERT_ARN" "$IMAGE"
preflight "$SERVICE" service -var-file="$WORK/service.tfvars"
# deploy.sh applies the same variables and, because the load balancer is
# internal, verifies through the ECS and ELB APIs.
TF_VAR_FILE="$WORK/service.tfvars" TF_SERVICE_DIR="$SERVICE" \
  "$REPO_ROOT/scripts/deploy.sh" "$IMAGE" "$RUN_ID" 2>&1 | sed "s|$SERVICE|<service>|g"

echo "--- live test passed"
