resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "enhanced"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

resource "aws_security_group" "tasks" {
  name        = "${var.name}-tasks"
  description = "Service tasks, reachable from the load balancer only"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "tasks_from_alb" {
  security_group_id            = aws_security_group.tasks.id
  description                  = "App port from the load balancer"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
}

resource "aws_vpc_security_group_egress_rule" "tasks_to_endpoints" {
  security_group_id            = aws_security_group.tasks.id
  description                  = "HTTPS to the VPC interface endpoints"
  referenced_security_group_id = aws_security_group.endpoints.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_egress_rule" "tasks_to_s3" {
  security_group_id = aws_security_group.tasks.id
  description       = "HTTPS to S3 through the gateway endpoint (image layers)"
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

locals {
  container_name = "app"

  container_definition = {
    name      = local.container_name
    image     = var.image
    essential = true

    portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]

    environment = [
      { name = "PORT", value = tostring(var.container_port) },
      { name = "APP_VERSION", value = var.app_version },
      { name = "LOG_LEVEL", value = var.log_level },
      { name = "SHUTDOWN_GRACE_SECONDS", value = "5" },
    ]

    # Same constraints as scripts/smoke-test.sh runs locally.
    user                   = "65532:65532"
    readonlyRootFilesystem = true
    privileged             = false
    linuxParameters = {
      capabilities       = { drop = ["ALL"] }
      initProcessEnabled = true
    }

    # Liveness probe inside the task; the target group checks /ready.
    healthCheck = {
      command     = ["CMD", "/nodejs/bin/node", "src/healthcheck.js"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 10
    }

    # ECS sends SIGTERM, waits stopTimeout seconds, then SIGKILL.
    stopTimeout = 30

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = local.region
        "awslogs-stream-prefix" = "app"
        "mode"                  = "non-blocking"
        "max-buffer-size"       = "25m"
      }
    }
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  container_definitions    = jsonencode([local.container_definition])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }
}

locals {
  service_network = {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }
}

# Rolling updates owned by ECS. The circuit breaker stops a deployment whose
# tasks keep failing to start or pass health checks and rolls back to the
# last completed deployment; the CloudWatch alarms do the same for a release
# that starts but serves errors. See docs/adr/0004-rolling-with-circuit-breaker-by-default.md.
resource "aws_ecs_service" "rolling" {
  count = local.codedeploy ? 0 : 1

  name                               = var.name
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.app.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  health_check_grace_period_seconds  = 30
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  availability_zone_rebalancing      = "ENABLED"
  enable_ecs_managed_tags            = true
  propagate_tags                     = "SERVICE"
  wait_for_steady_state              = true

  deployment_controller {
    type = "ECS"
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  alarms {
    enable      = true
    rollback    = true
    alarm_names = [aws_cloudwatch_metric_alarm.target_5xx.alarm_name, aws_cloudwatch_metric_alarm.unhealthy_hosts.alarm_name]
  }

  network_configuration {
    subnets          = local.service_network.subnets
    security_groups  = local.service_network.security_groups
    assign_public_ip = local.service_network.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = local.container_name
    container_port   = var.container_port
  }

  # Autoscaling owns the task count after creation.
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener.https, aws_lb_listener.https_codedeploy, aws_iam_role_policy.execution]
}

# Blue/green through CodeDeploy. CodeDeploy, not Terraform, moves the service
# to a new task definition and target group, so both are ignored here.
resource "aws_ecs_service" "codedeploy" {
  count = local.codedeploy ? 1 : 0

  name                              = var.name
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.app.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  platform_version                  = "LATEST"
  health_check_grace_period_seconds = 30
  enable_ecs_managed_tags           = true
  propagate_tags                    = "SERVICE"

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  network_configuration {
    subnets          = local.service_network.subnets
    security_groups  = local.service_network.security_groups
    assign_public_ip = local.service_network.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = local.container_name
    container_port   = var.container_port
  }

  lifecycle {
    ignore_changes = [desired_count, task_definition, load_balancer]
  }

  depends_on = [aws_lb_listener.https, aws_lb_listener.https_codedeploy, aws_iam_role_policy.execution]
}

locals {
  service_name = local.codedeploy ? aws_ecs_service.codedeploy[0].name : aws_ecs_service.rolling[0].name
}
