# Runbook: harbor-stock-api on ECS Fargate

Operating guide for the service this repository deploys. Names assume the default `name = "harbor-stock-api"` and
Region `us-east-1`. Harbor Goods is a fictional client; replace names and IDs with your own.

## At a glance

| Item | Value |
| --- | --- |
| Endpoint | `https://<your domain>` (CNAME or alias to the `alb_dns_name` output) |
| Liveness | `GET /health` answers 200 while the process runs |
| Readiness | `GET /ready` answers 503 once the task starts draining |
| Logs | CloudWatch Logs group `/ecs/harbor-stock-api`, one JSON line per request |
| Dashboard | CloudWatch dashboard `harbor-stock-api` |
| Alarms | `harbor-stock-api-target-5xx`, `harbor-stock-api-unhealthy-hosts`, `harbor-stock-api-p95-latency` |
| Deploys | `deploy` workflow on every merge to `main`, or `scripts/deploy.sh <image@sha256:...> <version>` |

## Deploy

The pipeline deploys on merge. To deploy by hand, with credentials for the target account:

```bash
TF_BACKEND_CONFIG=backend.hcl TF_VAR_FILE=production.tfvars \
  scripts/deploy.sh 111122223333.dkr.ecr.us-east-1.amazonaws.com/harbor-stock-api@sha256:<digest> <version>
```

The script refuses an image without a digest. It applies Terraform, starts a CodeDeploy deployment when the strategy
is `codedeploy`, then runs `scripts/verify-deployment.sh`.

## Roll back

Rolling strategy (default):

1. A failing release rolls back by itself: the circuit breaker handles tasks that never become healthy, and the
   target 5xx and unhealthy-host alarms handle tasks that start but serve errors.
2. To roll back a release that passed but is wrong, redeploy the previous digest. Find it in the workflow run summary
   ("Pushed ...") or with:

   ```bash
   aws ecr describe-images --repository-name harbor-stock-api \
     --query 'sort_by(imageDetails,&imagePushedAt)[-5:].[imagePushedAt,imageDigest,imageTags[0]]' --output table
   ```

   Then run `scripts/deploy.sh <repo>@<previous digest> <previous version>`.

CodeDeploy strategy:

1. During the 15 minutes after a traffic shift the old tasks still run. Stop the deployment with rollback:

   ```bash
   aws deploy stop-deployment --deployment-id <id> --auto-rollback-enabled
   ```

2. After that window, redeploy the previous digest as above.

## Scale

Autoscaling holds average CPU at `cpu_target_percent` (60) and, for the rolling strategy, requests per task at
`requests_per_target` (1,000 per minute), between `min_capacity` (2) and `max_capacity` (6). To change the limits,
edit the variables and apply. Avoid `aws ecs update-service --desired-count` for anything but an emergency: the next
scaling action overrides it.

## Investigate

| Symptom | Where to look | Likely cause |
| --- | --- | --- |
| 502 from the load balancer | Target group health, app logs around the time | Tasks restarting; check for `"msg":"close failed"` or crashes |
| 503 from the load balancer | Target group has no healthy targets | All tasks draining or failing `/ready` |
| Deployment rolled back | ECS service events, `aws ecs describe-services` | New image fails its health check or throws on start (bad `LOG_LEVEL`, `PORT`) |
| `CannotPullContainerError` | Task stopped reason | Endpoint security group or S3 gateway route missing, the image digest does not exist, or the image is in another account whose repository policy does not allow this one |
| Requests blocked (403) | WAF logs group `aws-waf-logs-harbor-stock-api` | Rate limit or a managed rule; check `terminatingRuleId` |

Useful Logs Insights query for the app log group:

```sql
fields @timestamp, status, path, durationMs, requestId
| filter msg = "request" and status >= 500
| sort @timestamp desc
| limit 50
```

## Shut down safely

ECS deregisters a task from the target group, waits for the 30-second deregistration delay, then sends SIGTERM. The
app flips `/ready` to 503, keeps serving in-flight requests for `SHUTDOWN_GRACE_SECONDS` (5), closes and exits 0.
ECS sends SIGKILL after `stopTimeout` (30 seconds).

## Hand over checklist

- [ ] DNS record points at the load balancer and the ACM certificate covers the name.
- [ ] `alarm_actions` lists an SNS topic someone reads.
- [ ] `deletion_protection = true` in production.
- [ ] The `production` GitHub environment requires a reviewer.
- [ ] The consultant's IAM access is removed.
