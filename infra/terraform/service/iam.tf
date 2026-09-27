# Task execution role: what the ECS agent needs to start the task (pull this
# one image, write to this one log group). There is no task role, because the
# app calls no AWS APIs; add one with its own policy when it does.

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

resource "aws_iam_role_policy" "execution" {
  name = "pull-image-and-write-logs"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # GetAuthorizationToken has no resource-level permissions.
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid      = "PullServiceImage"
        Effect   = "Allow"
        Action   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
        Resource = local.ecr_repository_arn
      },
      {
        Sid    = "WriteAppLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
        # Built from the name so it is known at plan time (tests assert it).
        Resource = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${aws_cloudwatch_log_group.app.name}:*"
      },
    ]
  })
}
