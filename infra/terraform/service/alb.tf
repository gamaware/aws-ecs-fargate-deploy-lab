# Public Application Load Balancer: HTTPS only (port 80 redirects), TLS 1.3
# policy, invalid headers dropped, access logs to S3.

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Public load balancer"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = toset(var.ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from clients"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  #checkov:skip=CKV_AWS_260:Port 80 only answers with a redirect to HTTPS (aws_lb_listener.http).
  for_each = toset(var.ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTP from clients, answered with a redirect to HTTPS"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "alb_test_listener" {
  for_each = local.codedeploy ? toset(var.test_listener_cidrs) : toset([])

  security_group_id = aws_security_group.alb.id
  description       = "CodeDeploy test listener"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 9443
  to_port           = 9443
}

resource "aws_vpc_security_group_egress_rule" "alb_to_tasks" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To the service tasks only"
  referenced_security_group_id = aws_security_group.tasks.id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
}

# Public by design: this load balancer is the service's internet entry point.
#trivy:ignore:AWS-0053
resource "aws_lb" "this" {
  #checkov:skip=CKV2_AWS_20:Port 80 exists only to redirect to HTTPS (aws_lb_listener.http).
  name                       = var.name
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = aws_subnet.public[*].id
  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection
  idle_timeout               = 60

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb"
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

resource "aws_lb_listener" "http" {
  #checkov:skip=CKV_AWS_2:This listener only answers with a permanent redirect to HTTPS.
  #checkov:skip=CKV_AWS_103:No TLS on a redirect-only listener.
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  count = local.codedeploy ? 0 : 1

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}

# Same listener for the CodeDeploy strategy. CodeDeploy switches its forward
# target between blue and green, so Terraform must not reset it.
resource "aws_lb_listener" "https_codedeploy" {
  count = local.codedeploy ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}

# Test listener for CodeDeploy: routes to the replacement (green) tasks before
# production traffic moves, so they can be checked first.
resource "aws_lb_listener" "test" {
  count = local.codedeploy ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 9443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green[0].arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}

locals {
  target_group_settings = {
    port                 = var.container_port
    protocol             = "HTTP"
    target_type          = "ip"
    deregistration_delay = 30
  }
}

resource "aws_lb_target_group" "blue" {
  name                 = "${var.name}-blue"
  vpc_id               = aws_vpc.this.id
  port                 = local.target_group_settings.port
  protocol             = local.target_group_settings.protocol
  target_type          = local.target_group_settings.target_type
  deregistration_delay = local.target_group_settings.deregistration_delay

  # /ready, not /health: the app answers 503 on /ready once it starts
  # draining, so the load balancer stops routing to it first.
  health_check {
    path                = "/ready"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "green" {
  count = local.codedeploy ? 1 : 0

  name                 = "${var.name}-green"
  vpc_id               = aws_vpc.this.id
  port                 = local.target_group_settings.port
  protocol             = local.target_group_settings.protocol
  target_type          = local.target_group_settings.target_type
  deregistration_delay = local.target_group_settings.deregistration_delay

  health_check {
    path                = "/ready"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# --- Access logs -------------------------------------------------------------

data "aws_elb_service_account" "this" {}

# This is the log bucket; logging it to itself would loop.
#trivy:ignore:AWS-0089
resource "aws_s3_bucket" "alb_logs" {
  #checkov:skip=CKV_AWS_144:Access logs are disposable operational data; cross-Region replication doubles cost for no recovery need.
  #checkov:skip=CKV2_AWS_62:Nothing consumes events for new log objects.
  #checkov:skip=CKV_AWS_18:This is the log bucket; logging it to itself would loop.
  #checkov:skip=CKV_AWS_145:ALB access log delivery supports SSE-S3 only, not SSE-KMS.
  bucket_prefix = "${var.name}-alb-logs-"
  force_destroy = !var.deletion_protection
}

resource "aws_s3_bucket_ownership_controls" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ALB access log delivery supports SSE-S3 only, not SSE-KMS.
#trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ElbLogDelivery"
        Effect    = "Allow"
        Principal = { AWS = data.aws_elb_service_account.this.arn }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs.arn}/alb/AWSLogs/${local.account_id}/*"
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.alb_logs.arn, "${aws_s3_bucket.alb_logs.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}
