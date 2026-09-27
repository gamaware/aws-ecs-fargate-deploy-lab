variable "name" {
  description = "Service name; prefixes every resource."
  type        = string
  default     = "harbor-stock-api"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,24}$", var.name))
    error_message = "name must be 3-25 lowercase letters, digits or hyphens (target group names cap at 32 characters)."
  }
}

variable "region" {
  description = "AWS Region for the service."
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Extra tags for every resource."
  type        = map(string)
  default     = {}
}

# --- Network ---------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block of the VPC. Split into one public and one private /20 per Availability Zone."
  type        = string
  default     = "10.40.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && tonumber(split("/", var.vpc_cidr)[1]) <= 18
    error_message = "vpc_cidr must be a valid IPv4 CIDR of /18 or larger."
  }
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets and tasks across."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3: an ALB needs two zones, and three keep the CIDR plan simple."
  }
}

variable "ingress_cidrs" {
  description = "Client CIDRs allowed to reach the load balancer on 80 and 443."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.ingress_cidrs) > 0 && alltrue([for c in var.ingress_cidrs : can(cidrnetmask(c))])
    error_message = "ingress_cidrs must hold at least one valid IPv4 CIDR."
  }
}

# --- Load balancer -----------------------------------------------------------

variable "certificate_arn" {
  description = "ACM certificate for the HTTPS listener. Port 80 only redirects to 443."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/[0-9a-f-]+$", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN."
  }
}

variable "deletion_protection" {
  description = "Protect the load balancer from deletion. Turn off only for disposable environments."
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Requests per 5 minutes from one IP before AWS WAF blocks it."
  type        = number
  default     = 2000

  validation {
    condition     = var.waf_rate_limit >= 100
    error_message = "waf_rate_limit must be at least 100 (the AWS WAF minimum is 10, but lower values block normal users)."
  }
}

# --- Container and task ------------------------------------------------------

variable "image" {
  description = "Container image pinned by digest, for example 111122223333.dkr.ecr.us-east-1.amazonaws.com/harbor-stock-api@sha256:<64 hex>."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/[a-z0-9][a-z0-9._/-]*@sha256:[0-9a-f]{64}$", var.image))
    error_message = "image must be an ECR image referenced by digest (repo@sha256:...), never by tag."
  }
}

variable "app_version" {
  description = "Version string passed to the app as APP_VERSION (the Git commit in CI)."
  type        = string
  default     = "dev"
}

variable "container_port" {
  description = "Port the app listens on inside the task."
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "Task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.cpu)
    error_message = "cpu must be a Fargate size: 256, 512, 1024, 2048 or 4096."
  }
}

variable "memory" {
  description = "Task memory in MiB; must be a valid Fargate pairing for cpu."
  type        = number
  default     = 512
}

variable "cpu_architecture" {
  description = "Task CPU architecture. ARM64 (Graviton) costs about 20% less than X86_64 for the same size; the image must match."
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture must be ARM64 or X86_64."
  }
}

variable "log_level" {
  description = "LOG_LEVEL for the app."
  type        = string
  default     = "info"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days for the app, VPC flow logs and WAF logs."
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a retention period CloudWatch Logs accepts."
  }
}

# --- Deployment and scaling --------------------------------------------------

variable "deployment_strategy" {
  description = "rolling: ECS rolling update with the deployment circuit breaker. codedeploy: blue/green through AWS CodeDeploy."
  type        = string
  default     = "rolling"

  validation {
    condition     = contains(["rolling", "codedeploy"], var.deployment_strategy)
    error_message = "deployment_strategy must be rolling or codedeploy."
  }
}

variable "codedeploy_config" {
  description = "CodeDeploy traffic-shift configuration, used when deployment_strategy is codedeploy."
  type        = string
  default     = "CodeDeployDefault.ECSCanary10Percent5Minutes"

  validation {
    condition     = can(regex("^CodeDeployDefault\\.ECS(AllAtOnce|Canary10Percent(5|15)Minutes|Linear10PercentEvery(1|3)Minutes)$", var.codedeploy_config))
    error_message = "codedeploy_config must be one of the CodeDeployDefault.ECS* configurations."
  }
}

variable "test_listener_cidrs" {
  description = "CIDRs allowed to reach the CodeDeploy test listener (port 9443) to check the green tasks before the shift. Empty = nobody."
  type        = list(string)
  default     = []
}

variable "desired_count" {
  description = "Tasks to start with; autoscaling adjusts it afterwards."
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Autoscaling floor. Two or more keeps a task in a second Availability Zone."
  type        = number
  default     = 2

  validation {
    condition     = var.min_capacity >= 1
    error_message = "min_capacity must be at least 1."
  }
}

variable "max_capacity" {
  description = "Autoscaling ceiling; caps cost during a traffic spike."
  type        = number
  default     = 6

  validation {
    condition     = var.max_capacity >= var.min_capacity
    error_message = "max_capacity must be greater than or equal to min_capacity."
  }
}

variable "cpu_target_percent" {
  description = "Average CPU utilization the service scales to hold."
  type        = number
  default     = 60

  validation {
    condition     = var.cpu_target_percent >= 20 && var.cpu_target_percent <= 90
    error_message = "cpu_target_percent must be between 20 and 90."
  }
}

variable "requests_per_target" {
  description = "ALB requests per task per minute the service scales to hold (rolling strategy only)."
  type        = number
  default     = 1000
}

variable "alarm_actions" {
  description = "SNS topic ARNs notified when an alarm fires. Rollback works without them."
  type        = list(string)
  default     = []
}
