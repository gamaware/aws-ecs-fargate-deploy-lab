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

variables {
  certificate_arn = "arn:aws:acm:us-east-1:111122223333:certificate/1f2e3d4c-5b6a-4789-8abc-def012345678"
  image           = "111122223333.dkr.ecr.us-east-1.amazonaws.com/harbor-stock-api@sha256:4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945"

  deployment_strategy = "codedeploy"
  test_listener_cidrs = ["198.51.100.0/24"]
}

# Optional strategy: blue/green through AWS CodeDeploy.

run "codedeploy_owns_the_deployment" {
  command = plan

  assert {
    condition     = length(aws_ecs_service.codedeploy) == 1 && length(aws_ecs_service.rolling) == 0
    error_message = "The codedeploy strategy creates exactly the CodeDeploy-controlled service."
  }

  assert {
    condition     = aws_ecs_service.codedeploy[0].deployment_controller[0].type == "CODE_DEPLOY"
    error_message = "The service must hand deployments to CodeDeploy."
  }

  assert {
    condition     = length(aws_lb_target_group.green) == 1 && length(aws_lb_listener.test) == 1
    error_message = "Blue/green needs a second target group and a test listener."
  }

  assert {
    condition     = aws_codedeploy_deployment_group.this[0].deployment_style[0].deployment_type == "BLUE_GREEN"
    error_message = "The deployment group must run blue/green deployments."
  }

  assert {
    condition     = toset(aws_codedeploy_deployment_group.this[0].auto_rollback_configuration[0].events) == toset(["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"])
    error_message = "CodeDeploy must roll back on failure and on alarm."
  }

  assert {
    condition     = length(aws_codedeploy_deployment_group.this[0].alarm_configuration[0].alarms) == 3
    error_message = "The 5xx alarm and an unhealthy-host alarm per target group guard blue/green deployments."
  }

  assert {
    condition     = length(aws_appautoscaling_policy.requests) == 0 && aws_appautoscaling_policy.cpu.name == "harbor-stock-api-cpu"
    error_message = "Under CodeDeploy the service scales on CPU only."
  }

  assert {
    condition     = output.codedeploy_deployment_group_name == "harbor-stock-api"
    error_message = "The deployment group name must be exported for the deploy script."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.alb_test_listener) == 1
    error_message = "Only the listed CIDRs may reach the test listener."
  }
}
