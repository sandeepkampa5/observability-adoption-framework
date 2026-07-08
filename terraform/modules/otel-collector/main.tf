# =============================================================================
# Enterprise Observability Adoption Framework
# Terraform Module: OTel Collector Gateway
#
# Based on architectural patterns from:
# - "Adoption of RUM and APM at Splunk" (March 2024)
# - "Adoption of Infrastructure Monitoring at Splunk" (July 2024)
# - Splunk-on-Splunk .conf2023 Reference Architecture
#
# Author: Sandeep Kampa
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# =============================================================================
# VARIABLES
# =============================================================================

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "vpc_id" {
  description = "VPC ID for the OTel Collector deployment"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the OTel Collector fleet"
  type        = list(string)
}

variable "cluster_name" {
  description = "ECS cluster name for the collector fleet"
  type        = string
  default     = "otel-collector-fleet"
}

variable "collector_image" {
  description = "Docker image for the OTel Collector"
  type        = string
  default     = "otel/opentelemetry-collector-contrib:0.100.0"
}

variable "desired_count" {
  description = "Number of collector instances"
  type        = number
  default     = 2
}

variable "cpu" {
  description = "CPU units for each collector task (1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "memory" {
  description = "Memory (MiB) for each collector task"
  type        = number
  default     = 2048
}

variable "observability_backend" {
  description = "Target observability backend configuration"
  type = object({
    type        = string # splunk, datadog, grafana, newrelic, aws, elastic, oss
    endpoint    = string
    token_arn   = string # ARN of the secret containing the API token
    region      = optional(string, "")
  })
}

variable "enable_rum_receiver" {
  description = "Enable the RUM/browser telemetry receiver"
  type        = bool
  default     = true
}

variable "enable_infrastructure_metrics" {
  description = "Enable infrastructure metrics collection (host, container)"
  type        = bool
  default     = true
}

variable "enable_apm_traces" {
  description = "Enable APM distributed tracing"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# LOCALS
# =============================================================================

locals {
  name_prefix = "o11y-${var.environment}"
  
  common_tags = merge(var.tags, {
    Environment = var.environment
    Framework   = "observability-adoption-framework"
    ManagedBy   = "terraform"
  })

  # Adoption phase determines which pipelines are active
  # Phase 1: Infrastructure metrics only
  # Phase 2: + APM traces
  # Phase 3: + RUM telemetry
  # Phase 4: Full stack + alerting
  active_pipelines = compact([
    var.enable_infrastructure_metrics ? "metrics" : "",
    var.enable_apm_traces ? "traces" : "",
    var.enable_rum_receiver ? "rum" : "",
  ])
}

# =============================================================================
# SECURITY GROUP
# =============================================================================

resource "aws_security_group" "collector" {
  name_prefix = "${local.name_prefix}-collector-"
  vpc_id      = var.vpc_id
  description = "Security group for OTel Collector Gateway"

  # OTLP gRPC
  ingress {
    from_port   = 4317
    to_port     = 4317
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "OTLP gRPC receiver"
  }

  # OTLP HTTP
  ingress {
    from_port   = 4318
    to_port     = 4318
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "OTLP HTTP receiver"
  }

  # Jaeger receiver
  ingress {
    from_port   = 14250
    to_port     = 14250
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "Jaeger gRPC receiver"
  }

  # Zipkin receiver
  ingress {
    from_port   = 9411
    to_port     = 9411
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "Zipkin receiver"
  }

  # Prometheus scrape endpoint
  ingress {
    from_port   = 8888
    to_port     = 8888
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "Prometheus metrics (self-monitoring)"
  }

  # Health check
  ingress {
    from_port   = 13133
    to_port     = 13133
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "Health check extension"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound (to reach observability backends)"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-collector-sg"
  })
}

# =============================================================================
# ECS CLUSTER
# =============================================================================

resource "aws_ecs_cluster" "collector" {
  name = "${local.name_prefix}-${var.cluster_name}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

resource "aws_ecs_cluster_capacity_providers" "collector" {
  cluster_name       = aws_ecs_cluster.collector.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 1
    capacity_provider = "FARGATE"
  }

  default_capacity_provider_strategy {
    weight            = 3
    capacity_provider = "FARGATE_SPOT"
  }
}

# =============================================================================
# IAM ROLE
# =============================================================================

resource "aws_iam_role" "collector_task" {
  name_prefix = "${local.name_prefix}-collector-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "collector_secrets" {
  name_prefix = "secrets-access-"
  role        = aws_iam_role.collector_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [var.observability_backend.token_arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "collector_execution" {
  role       = aws_iam_role.collector_task.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# =============================================================================
# CLOUDWATCH LOG GROUP
# =============================================================================

resource "aws_cloudwatch_log_group" "collector" {
  name              = "/ecs/${local.name_prefix}-collector"
  retention_in_days = var.environment == "prod" ? 30 : 7

  tags = local.common_tags
}

# =============================================================================
# ECS TASK DEFINITION
# =============================================================================

resource "aws_ecs_task_definition" "collector" {
  family                   = "${local.name_prefix}-collector"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.collector_task.arn
  task_role_arn            = aws_iam_role.collector_task.arn

  container_definitions = jsonencode([
    {
      name  = "otel-collector"
      image = var.collector_image
      
      essential = true

      portMappings = [
        { containerPort = 4317, protocol = "tcp" },  # OTLP gRPC
        { containerPort = 4318, protocol = "tcp" },  # OTLP HTTP
        { containerPort = 14250, protocol = "tcp" }, # Jaeger
        { containerPort = 9411, protocol = "tcp" },  # Zipkin
        { containerPort = 8888, protocol = "tcp" },  # Prometheus self-metrics
        { containerPort = 13133, protocol = "tcp" }, # Health check
      ]

      environment = [
        {
          name  = "OTEL_BACKEND_TYPE"
          value = var.observability_backend.type
        },
        {
          name  = "OTEL_BACKEND_ENDPOINT"
          value = var.observability_backend.endpoint
        },
        {
          name  = "OTEL_BACKEND_REGION"
          value = var.observability_backend.region
        },
        {
          name  = "ENABLE_RUM"
          value = tostring(var.enable_rum_receiver)
        },
        {
          name  = "ENABLE_APM"
          value = tostring(var.enable_apm_traces)
        },
        {
          name  = "ENABLE_INFRA"
          value = tostring(var.enable_infrastructure_metrics)
        },
      ]

      secrets = [
        {
          name      = "OTEL_BACKEND_TOKEN"
          valueFrom = var.observability_backend.token_arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.collector.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "collector"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget --spider -q http://localhost:13133/ || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }
    }
  ])

  tags = local.common_tags
}

# =============================================================================
# ECS SERVICE
# =============================================================================

resource "aws_ecs_service" "collector" {
  name            = "${local.name_prefix}-collector"
  cluster         = aws_ecs_cluster.collector.id
  task_definition = aws_ecs_task_definition.collector.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.collector.id]
    assign_public_ip = false
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = local.common_tags
}

# =============================================================================
# AUTO SCALING
# =============================================================================

resource "aws_appautoscaling_target" "collector" {
  max_capacity       = var.desired_count * 4
  min_capacity       = var.desired_count
  resource_id        = "service/${aws_ecs_cluster.collector.name}/${aws_ecs_service.collector.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "collector_cpu" {
  name               = "${local.name_prefix}-collector-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.collector.resource_id
  scalable_dimension = aws_appautoscaling_target.collector.scalable_dimension
  service_namespace  = aws_appautoscaling_target.collector.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# =============================================================================
# DATA SOURCES
# =============================================================================

data "aws_region" "current" {}

# =============================================================================
# OUTPUTS
# =============================================================================

output "cluster_id" {
  description = "ECS Cluster ID"
  value       = aws_ecs_cluster.collector.id
}

output "service_name" {
  description = "ECS Service name"
  value       = aws_ecs_service.collector.name
}

output "security_group_id" {
  description = "Security Group ID for the collector fleet"
  value       = aws_security_group.collector.id
}

output "collector_endpoints" {
  description = "Collector receiver endpoints"
  value = {
    otlp_grpc = "otel-collector.${var.environment}.internal:4317"
    otlp_http = "otel-collector.${var.environment}.internal:4318"
    jaeger    = "otel-collector.${var.environment}.internal:14250"
    zipkin    = "otel-collector.${var.environment}.internal:9411"
  }
}

output "active_pipelines" {
  description = "Currently active telemetry pipelines"
  value       = local.active_pipelines
}
