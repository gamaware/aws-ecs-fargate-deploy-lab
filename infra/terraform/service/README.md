# service stack

Network, load balancer, AWS WAF, ECS cluster and service, autoscaling, alarms, dashboard, and the optional CodeDeploy
blue/green resources. The pipeline applies it on every deploy with a new `image` digest (see
[scripts/deploy.sh](../../../scripts/deploy.sh)).

```bash
cp terraform.tfvars.example terraform.tfvars   # set certificate_arn and image
terraform init -backend-config=backend.hcl
terraform apply
```

Tests run offline against a mocked provider: `terraform test` (`tests/rolling.tftest.hcl`,
`tests/codedeploy.tftest.hcl`, `tests/validation.tftest.hcl`, `tests/live_private.tftest.hcl`).

`private_only = true` builds the stack with no internet path: no internet gateway, public subnets or default route,
an internal load balancer in the private subnets, and client ingress from the VPC CIDR only. `make test-live` always
sets it; `tests/live_private.tftest.hcl` fails if that configuration would create anything internet-facing.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11.0, < 2.0.0 |
| aws | ~> 6.66 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | 6.66.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_appautoscaling_policy.cpu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy) | resource |
| [aws_appautoscaling_policy.requests](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy) | resource |
| [aws_appautoscaling_target.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_target) | resource |
| [aws_cloudwatch_dashboard.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_dashboard) | resource |
| [aws_cloudwatch_log_group.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.waf](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.p95_latency](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.target_5xx](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.unhealthy_hosts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.unhealthy_hosts_green](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_codedeploy_app.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codedeploy_app) | resource |
| [aws_codedeploy_deployment_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codedeploy_deployment_group) | resource |
| [aws_default_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) | resource |
| [aws_ecs_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_cluster_capacity_providers.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster_capacity_providers) | resource |
| [aws_ecs_service.codedeploy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_service.rolling](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_role.codedeploy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.codedeploy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_kms_alias.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_lb.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.https_codedeploy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.test](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.blue](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group.green](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_route.public_internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_s3_bucket.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_security_group.alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.tasks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.interface](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_security_group_egress_rule.alb_to_tasks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.tasks_to_endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.tasks_to_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.alb_http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.alb_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.alb_test_listener](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.endpoints_from_tasks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.tasks_from_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_wafv2_web_acl.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl) | resource |
| [aws_wafv2_web_acl_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association) | resource |
| [aws_wafv2_web_acl_logging_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_logging_configuration) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_elb_service_account.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/elb_service_account) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| certificate\_arn | ACM certificate for the HTTPS listener. Port 80 only redirects to 443. | `string` | n/a | yes |
| image | Container image pinned by digest, for example 111122223333.dkr.ecr.us-east-1.amazonaws.com/harbor-stock-api@sha256:<64 hex>. | `string` | n/a | yes |
| alarm\_actions | SNS topic ARNs notified when an alarm fires. Rollback works without them. | `list(string)` | `[]` | no |
| app\_version | Version string passed to the app as APP\_VERSION (the Git commit in CI). | `string` | `"dev"` | no |
| az\_count | Number of Availability Zones to spread subnets and tasks across. | `number` | `2` | no |
| codedeploy\_config | CodeDeploy traffic-shift configuration, used when deployment\_strategy is codedeploy. | `string` | `"CodeDeployDefault.ECSCanary10Percent5Minutes"` | no |
| container\_port | Port the app listens on inside the task. | `number` | `8080` | no |
| cpu | Task CPU units (256 = 0.25 vCPU). | `number` | `256` | no |
| cpu\_architecture | Task CPU architecture. ARM64 (Graviton) costs about 20% less than X86\_64 for the same size; the image must match. | `string` | `"ARM64"` | no |
| cpu\_target\_percent | Average CPU utilization the service scales to hold. | `number` | `60` | no |
| deletion\_protection | Protect the load balancer from deletion. Turn off only for disposable environments. | `bool` | `true` | no |
| deployment\_strategy | rolling: ECS rolling update with the deployment circuit breaker. codedeploy: blue/green through AWS CodeDeploy. | `string` | `"rolling"` | no |
| desired\_count | Tasks to start with; autoscaling adjusts it afterwards. | `number` | `2` | no |
| ingress\_cidrs | Client CIDRs allowed to reach the load balancer on 80 and 443. Ignored when private\_only is true. | `list(string)` | ```[ "0.0.0.0/0" ]``` | no |
| log\_level | LOG\_LEVEL for the app. | `string` | `"info"` | no |
| log\_retention\_days | CloudWatch Logs retention in days for the app, VPC flow logs and WAF logs. | `number` | `365` | no |
| max\_capacity | Autoscaling ceiling; caps cost during a traffic spike. | `number` | `6` | no |
| memory | Task memory in MiB; must be a valid Fargate pairing for cpu. | `number` | `512` | no |
| min\_capacity | Autoscaling floor. Two or more keeps a task in a second Availability Zone. | `number` | `2` | no |
| name | Service name; prefixes every resource. | `string` | `"harbor-stock-api"` | no |
| private\_only | Build no internet path: no internet gateway or public subnets, an internal load balancer in the private subnets, and client ingress from the VPC CIDR only (ingress\_cidrs is ignored). make test-live sets it to true. | `bool` | `false` | no |
| region | AWS Region for the service. | `string` | `"us-east-1"` | no |
| requests\_per\_target | ALB requests per task per minute the service scales to hold (rolling strategy only). | `number` | `1000` | no |
| tags | Extra tags for every resource. | `map(string)` | `{}` | no |
| test\_listener\_cidrs | CIDRs allowed to reach the CodeDeploy test listener (port 9443) to check the green tasks before the shift. Empty = nobody. | `list(string)` | `[]` | no |
| vpc\_cidr | CIDR block of the VPC. Split into one public and one private /20 per Availability Zone. | `string` | `"10.40.0.0/16"` | no |
| waf\_rate\_limit | Requests per 5 minutes from one IP before AWS WAF blocks it. | `number` | `2000` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| alb\_arn | Load balancer ARN (make test-live reads target health through it). |
| alb\_dns\_name | Load balancer DNS name; point the service's DNS record (CNAME or alias) at it. |
| alb\_internal | true when the load balancer is internal (private\_only). |
| alb\_zone\_id | Hosted zone ID of the load balancer, for a Route 53 alias record. |
| cluster\_name | ECS cluster name. |
| codedeploy\_app\_name | CodeDeploy application (null for the rolling strategy). |
| codedeploy\_deployment\_group\_name | CodeDeploy deployment group (null for the rolling strategy). |
| container\_name | Container name in the task definition (used in the CodeDeploy AppSpec). |
| container\_port | Container port behind the load balancer (used in the CodeDeploy AppSpec). |
| deployment\_strategy | rolling or codedeploy. |
| log\_group\_name | CloudWatch log group with the app logs. |
| service\_name | ECS service name. |
| task\_definition\_arn | Task definition revision that runs the requested image. |
<!-- END_TF_DOCS -->
