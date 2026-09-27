output "alb_dns_name" {
  description = "Load balancer DNS name; point the service's DNS record (CNAME or alias) at it."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the load balancer, for a Route 53 alias record."
  value       = aws_lb.this.zone_id
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "ECS service name."
  value       = local.service_name
}

output "task_definition_arn" {
  description = "Task definition revision that runs the requested image."
  value       = aws_ecs_task_definition.app.arn
}

output "container_name" {
  description = "Container name in the task definition (used in the CodeDeploy AppSpec)."
  value       = local.container_name
}

output "container_port" {
  description = "Container port behind the load balancer (used in the CodeDeploy AppSpec)."
  value       = var.container_port
}

output "log_group_name" {
  description = "CloudWatch log group with the app logs."
  value       = aws_cloudwatch_log_group.app.name
}

output "deployment_strategy" {
  description = "rolling or codedeploy."
  value       = var.deployment_strategy
}

output "codedeploy_app_name" {
  description = "CodeDeploy application (null for the rolling strategy)."
  value       = one(aws_codedeploy_app.this[*].name)
}

output "codedeploy_deployment_group_name" {
  description = "CodeDeploy deployment group (null for the rolling strategy)."
  value       = one(aws_codedeploy_deployment_group.this[*].deployment_group_name)
}
