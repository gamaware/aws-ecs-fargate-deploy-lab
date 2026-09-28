data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:Only the first var.az_count zones, in sorted name order, are used; a new zone does not change them.
  state = "available"
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  azs        = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  codedeploy = var.deployment_strategy == "codedeploy"
}
