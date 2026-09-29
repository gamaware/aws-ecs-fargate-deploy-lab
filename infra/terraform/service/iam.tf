# Task execution role: what the ECS agent needs to start the task (pull the
# image from ECR, write to CloudWatch Logs). It uses the AWS managed
# AmazonECSTaskExecutionRolePolicy, maintained by AWS for exactly this role.
# Its pull and log actions apply to every repository and log group in the
# account. A scoped inline policy would narrow those to this service's
# repository and log group, but it still has to grant
# ecr:GetAuthorizationToken on "*" (the action has no resource-level scope).
# The trust policy is scoped to this account's ECS tasks. There is no task
# role, because the app calls no AWS APIs; add one with its own policy when it
# does.

resource "aws_iam_role" "execution" {
  name = "${var.name}-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:*" }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
