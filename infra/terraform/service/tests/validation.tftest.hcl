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
    values = { arn = "arn:aws:iam::127311923021:root" }
  }
}

variables {
  certificate_arn = "arn:aws:acm:us-east-1:111122223333:certificate/1f2e3d4c-5b6a-4789-8abc-def012345678"
  image           = "111122223333.dkr.ecr.us-east-1.amazonaws.com/harbor-stock-api@sha256:4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945"
}

# Inputs that must be rejected before anything is planned.

run "rejects_an_image_referenced_by_tag" {
  command = plan

  variables {
    image = "111122223333.dkr.ecr.us-east-1.amazonaws.com/harbor-stock-api:latest"
  }

  expect_failures = [var.image]
}

run "rejects_an_image_outside_ecr" {
  command = plan

  variables {
    image = "docker.io/library/nginx@sha256:4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945"
  }

  expect_failures = [var.image]
}

run "rejects_an_unknown_strategy" {
  command = plan

  variables {
    deployment_strategy = "recreate"
  }

  expect_failures = [var.deployment_strategy]
}

run "rejects_max_below_min_capacity" {
  command = plan

  variables {
    min_capacity = 4
    max_capacity = 2
  }

  expect_failures = [var.max_capacity]
}

run "rejects_a_single_availability_zone" {
  command = plan

  variables {
    az_count = 1
  }

  expect_failures = [var.az_count]
}

run "rejects_a_non_acm_certificate" {
  command = plan

  variables {
    certificate_arn = "arn:aws:iam::111122223333:server-certificate/harbor"
  }

  expect_failures = [var.certificate_arn]
}
