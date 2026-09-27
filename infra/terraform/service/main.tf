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

  # Parsed from the digest-pinned image, so the execution role can pull from
  # exactly that repository and nothing else.
  image_parts        = regex("^([0-9]{12})\\.dkr\\.ecr\\.([a-z0-9-]+)\\.amazonaws\\.com/([^@]+)@", var.image)
  ecr_repository_arn = "arn:${local.partition}:ecr:${local.image_parts[1]}:${local.image_parts[0]}:repository/${local.image_parts[2]}"

  codedeploy = var.deployment_strategy == "codedeploy"
}
