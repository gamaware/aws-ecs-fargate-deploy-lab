# Offline: the mocked provider never calls AWS and needs no credentials.
# Account 111122223333 is the AWS documentation example ID.
#
# The variables below are the ones scripts/test-live.sh writes for a live run
# (private_only = true). A live run must not create anything reachable from
# the internet; these runs fail if that configuration turns public again.
# scripts/check_private_plan.py enforces the same rules on the real plan
# before test-live.sh applies anything.
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
  name                = "harbor-test-123456"
  region              = "us-east-1"
  certificate_arn     = "arn:aws:acm:us-east-1:111122223333:certificate/1f2e3d4c-5b6a-4789-8abc-def012345678"
  deployment_strategy = "rolling"
  deletion_protection = false
  log_retention_days  = 1
  image               = "111122223333.dkr.ecr.us-east-1.amazonaws.com/harbor-test-123456@sha256:4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945"
  app_version         = "123456"
  tags                = { purpose = "portfolio-test", run = "123456" }
  private_only        = true
}

run "live_rolling_has_no_internet_path" {
  command = plan

  assert {
    condition     = aws_lb.this.internal == true
    error_message = "The live-test load balancer must be internal."
  }

  assert {
    condition     = length(aws_internet_gateway.this) == 0
    error_message = "A live run must not create an internet gateway."
  }

  assert {
    condition     = length(aws_route.public_internet) == 0 && length(aws_route_table.public) == 0
    error_message = "A live run must not create a default route to an internet gateway."
  }

  assert {
    condition     = length(aws_subnet.public) == 0 && length(aws_route_table_association.public) == 0
    error_message = "A live run must not create public subnets."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : !coalesce(s.map_public_ip_on_launch, false)])
    error_message = "Subnets must not map public IP addresses on launch."
  }

  assert {
    condition = alltrue([
      for r in concat(
        values(aws_vpc_security_group_ingress_rule.alb_https),
        values(aws_vpc_security_group_ingress_rule.alb_http),
        values(aws_vpc_security_group_ingress_rule.alb_test_listener),
      ) : !contains(["0.0.0.0/0", "::/0"], coalesce(r.cidr_ipv4, r.cidr_ipv6, "none"))
    ])
    error_message = "No security group may accept ingress from 0.0.0.0/0 or ::/0."
  }

  assert {
    condition     = keys(aws_vpc_security_group_ingress_rule.alb_https) == [var.vpc_cidr]
    error_message = "Clients reach the internal load balancer from the VPC CIDR only."
  }

  assert {
    condition     = aws_ecs_service.rolling[0].network_configuration[0].assign_public_ip == false
    error_message = "Tasks must run with assign_public_ip = false."
  }
}

run "live_codedeploy_has_no_internet_path" {
  command = plan

  variables {
    deployment_strategy = "codedeploy"
  }

  assert {
    condition     = aws_lb.this.internal == true
    error_message = "The live-test load balancer must be internal."
  }

  assert {
    condition     = length(aws_internet_gateway.this) == 0 && length(aws_route.public_internet) == 0 && length(aws_subnet.public) == 0
    error_message = "A live run must not create an internet gateway, a default route or public subnets."
  }

  assert {
    condition     = aws_ecs_service.codedeploy[0].network_configuration[0].assign_public_ip == false
    error_message = "Tasks must run with assign_public_ip = false."
  }

  assert {
    condition = alltrue([
      for r in concat(
        values(aws_vpc_security_group_ingress_rule.alb_https),
        values(aws_vpc_security_group_ingress_rule.alb_http),
        values(aws_vpc_security_group_ingress_rule.alb_test_listener),
      ) : !contains(["0.0.0.0/0", "::/0"], coalesce(r.cidr_ipv4, r.cidr_ipv6, "none"))
    ])
    error_message = "No security group may accept ingress from 0.0.0.0/0 or ::/0."
  }
}

run "private_only_ignores_world_ingress_cidrs" {
  command = plan

  variables {
    ingress_cidrs = ["0.0.0.0/0"]
  }

  assert {
    condition     = keys(aws_vpc_security_group_ingress_rule.alb_https) == [var.vpc_cidr] && keys(aws_vpc_security_group_ingress_rule.alb_http) == [var.vpc_cidr]
    error_message = "private_only must replace ingress_cidrs with the VPC CIDR."
  }
}

run "private_only_rejects_a_world_test_listener" {
  command = plan

  variables {
    deployment_strategy = "codedeploy"
    test_listener_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.test_listener_cidrs]
}
