# Optional blue/green deployments (deployment_strategy = "codedeploy").
# See docs/adr/0005-codedeploy-blue-green-as-an-option.md.

resource "aws_iam_role" "codedeploy" {
  count = local.codedeploy ? 1 : 0

  name = "${var.name}-codedeploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy" {
  count = local.codedeploy ? 1 : 0

  role       = aws_iam_role.codedeploy[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AWSCodeDeployRoleForECS"
}

resource "aws_codedeploy_app" "this" {
  count = local.codedeploy ? 1 : 0

  name             = var.name
  compute_platform = "ECS"
}

resource "aws_codedeploy_deployment_group" "this" {
  count = local.codedeploy ? 1 : 0

  app_name               = aws_codedeploy_app.this[0].name
  deployment_group_name  = var.name
  deployment_config_name = var.codedeploy_config
  service_role_arn       = aws_iam_role.codedeploy[0].arn

  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    # Keep the old (blue) tasks for 15 minutes after the shift, so a rollback
    # is a listener switch rather than a fresh deployment.
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 15
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  alarm_configuration {
    enabled = true
    alarms = [
      aws_cloudwatch_metric_alarm.target_5xx.alarm_name,
      aws_cloudwatch_metric_alarm.unhealthy_hosts.alarm_name,
      aws_cloudwatch_metric_alarm.unhealthy_hosts_green[0].alarm_name,
    ]
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.this.name
    service_name = aws_ecs_service.codedeploy[0].name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.https_codedeploy[0].arn]
      }

      test_traffic_route {
        listener_arns = [aws_lb_listener.test[0].arn]
      }

      target_group {
        name = aws_lb_target_group.blue.name
      }

      target_group {
        name = aws_lb_target_group.green[0].name
      }
    }
  }

  depends_on = [aws_iam_role_policy_attachment.codedeploy]
}
