# Offline: the mocked provider never calls AWS and needs no credentials.
# Account 111122223333 is the AWS documentation example ID.
mock_provider "aws" {
  override_data {
    target = data.aws_availability_zones.available
    values = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "111122223333" }
  }
  override_data {
    target = data.aws_partition.current
    values = { partition = "aws" }
  }
  override_data {
    target = data.aws_region.current
    values = { region = "us-east-1" }
  }
  override_data {
    target = data.aws_elb_service_account.this
    values = { arn = "arn:aws:iam::111122223333:root" }
  }
}

# A known ARN at plan time, so the WAF logging destination can be asserted.
override_resource {
  target          = aws_cloudwatch_log_group.waf
  override_during = plan
  values          = { arn = "arn:aws:logs:us-east-1:111122223333:log-group:aws-waf-logs-harbor-stock-api" }
}

variables {
  certificate_arn = "arn:aws:acm:us-east-1:111122223333:certificate/1f2e3d4c-5b6a-4789-8abc-def012345678"
  image           = "111122223333.dkr.ecr.us-east-1.amazonaws.com/harbor-stock-api@sha256:4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945"
}

# Default strategy: ECS rolling updates guarded by the circuit breaker.

run "circuit_breaker_and_alarms_roll_back_a_bad_release" {
  command = plan

  assert {
    condition     = length(aws_ecs_service.rolling) == 1 && length(aws_ecs_service.codedeploy) == 0
    error_message = "The rolling strategy creates exactly the ECS-controlled service."
  }

  assert {
    condition     = aws_ecs_service.rolling[0].deployment_circuit_breaker[0].enable && aws_ecs_service.rolling[0].deployment_circuit_breaker[0].rollback
    error_message = "The deployment circuit breaker must be on, with automatic rollback."
  }

  assert {
    condition     = aws_ecs_service.rolling[0].alarms[0].rollback && length(aws_ecs_service.rolling[0].alarms[0].alarm_names) == 2
    error_message = "The 5xx and unhealthy-host alarms must roll back a deployment."
  }

  assert {
    condition     = aws_ecs_service.rolling[0].deployment_minimum_healthy_percent == 100
    error_message = "A rolling deployment must never drop below full capacity."
  }

  assert {
    condition     = length(aws_codedeploy_deployment_group.this) == 0 && length(aws_lb_target_group.green) == 0
    error_message = "No CodeDeploy resources in rolling mode."
  }
}

run "tasks_are_private_and_locked_down" {
  command = plan

  assert {
    condition     = aws_ecs_service.rolling[0].network_configuration[0].assign_public_ip == false
    error_message = "Tasks must not get public IP addresses."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].image == var.image
    error_message = "The task must run exactly the digest-pinned image."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].readonlyRootFilesystem
    error_message = "The root filesystem must be read-only."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].user == "65532:65532"
    error_message = "The container must run as the non-root distroless user."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].linuxParameters.capabilities.drop == ["ALL"]
    error_message = "All Linux capabilities must be dropped."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].logConfiguration.options["awslogs-group"] == "/ecs/harbor-stock-api"
    error_message = "App logs must go to the service log group."
  }

  assert {
    condition     = aws_ecs_task_definition.app.runtime_platform[0].cpu_architecture == "ARM64"
    error_message = "The default architecture is ARM64 (Graviton)."
  }
}

run "execution_role_uses_the_managed_policy_and_a_scoped_trust" {
  command = plan

  assert {
    condition     = aws_iam_role_policy_attachment.execution.policy_arn == "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
    error_message = "The execution role must use the AWS managed ECS task execution policy."
  }

  assert {
    condition     = jsondecode(aws_iam_role.execution.assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "111122223333"
    error_message = "Only ECS tasks in this account may assume the execution role."
  }
}

run "load_balancer_serves_https_only" {
  command = plan

  assert {
    condition     = aws_lb_listener.http.default_action[0].type == "redirect" && aws_lb_listener.http.default_action[0].redirect[0].protocol == "HTTPS"
    error_message = "Port 80 must only redirect to HTTPS."
  }

  assert {
    condition     = startswith(aws_lb_listener.https[0].ssl_policy, "ELBSecurityPolicy-TLS13")
    error_message = "The HTTPS listener must use an ELBSecurityPolicy-TLS13 policy (TLS 1.2 and 1.3)."
  }

  assert {
    condition     = aws_lb.this.drop_invalid_header_fields && aws_lb.this.enable_deletion_protection
    error_message = "The load balancer must drop invalid headers and be deletion-protected by default."
  }

  assert {
    condition     = aws_lb_target_group.blue.health_check[0].path == "/ready"
    error_message = "The target group must check /ready so draining tasks leave rotation first."
  }

  assert {
    condition     = contains([for r in aws_wafv2_web_acl.this.rule : r.name], "per-ip-rate-limit")
    error_message = "AWS WAF must rate-limit each client IP."
  }

  assert {
    condition     = aws_cloudwatch_log_group.waf.name == "aws-waf-logs-harbor-stock-api"
    error_message = "AWS WAF logs must go to a log group whose name starts with aws-waf-logs-."
  }

  assert {
    condition     = aws_wafv2_web_acl_logging_configuration.this.log_destination_configs == toset([aws_cloudwatch_log_group.waf.arn])
    error_message = "The web ACL must log to the WAF log group."
  }
}

run "autoscaling_tracks_cpu_and_requests" {
  command = plan

  variables {
    min_capacity = 3
    max_capacity = 10
  }

  assert {
    condition     = aws_appautoscaling_target.service.min_capacity == 3 && aws_appautoscaling_target.service.max_capacity == 10
    error_message = "Autoscaling bounds must follow the variables."
  }

  assert {
    condition     = aws_appautoscaling_target.service.resource_id == "service/harbor-stock-api/harbor-stock-api"
    error_message = "Autoscaling must target the service."
  }

  assert {
    condition     = length(aws_appautoscaling_policy.requests) == 1
    error_message = "Rolling mode scales on requests per target as well as CPU."
  }
}
