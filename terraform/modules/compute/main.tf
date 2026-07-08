# =============================================================================
# Enterprise Observability Adoption Framework
# Terraform Module: Compute (Application Workloads)
#
# Deploys auto-instrumented application services on ECS Fargate with
# OTel sidecar injection. These are the workloads that EMIT telemetry
# to the OTel Collector Gateway.
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
}

variable "vpc_id" {
  description = "VPC ID for application deployment"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for application tasks"
  type        = list(string)
}

variable "service_name" {
  description = "Name of the application service"
  type        = string
}

variable "container_image" {
  description = "Docker image for the application"
  type        = string
}

variable "container_port" {
  description = "Port the application listens on"
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "CPU units for the application task"
  type        = number
  default     = 512
}

variable "memory" {
  description = "Memory (MiB) for the application task"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Number of application instances"
  type        = number
  default     = 2
}

variable "otel_collector_endpoint" {
  description = "OTel Collector Gateway gRPC endpoint"
  type        = string
}

variable "enable_auto_instrumentation" {
  description = "Inject OTel auto-instrumentation sidecar"
  type        = bool
  default     = true
}

variable "otel_sdk_language" {
  description = "Language for OTel auto-instrumentation (java, python, nodejs, dotnet)"
  type        = string
  default     = "java"
  validation {
    condition     = contains(["java", "python", "nodejs", "dotnet"], var.otel_sdk_language)
    error_message = "Supported languages: java, python, nodejs, dotnet."
  }
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
  name_prefix = "o11y-${var.environment}-${var.service_name}"

  common_tags = merge(var.tags, {
    Environment = var.environment
    Service     = var.service_name
    Framework   = "observability-adoption-framework"
    ManagedBy   = "terraform"
  })

  # OTel auto-instrumentation agent images per language
  otel_agent_images = {
    java   = "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:2.4.0"
    python = "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-python:0.44b0"
    nodejs = "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:0.49.1"
    dotnet = "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-dotnet:1.5.0"
  }
}

# =============================================================================
# IAM ROLE
# =============================================================================

resource "aws_iam_role" "app_task" {
  name_prefix = "${local.name_prefix}-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "app_execution" {
  role       = aws_iam_role.app_task.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# =============================================================================
# CLOUDWATCH LOG GROUP
# =============================================================================

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = var.environment == "prod" ? 30 : 7
  tags              = local.common_tags
}

# =============================================================================
# ECS TASK DEFINITION (with OTel sidecar)
# =============================================================================

resource "aws_ecs_task_definition" "app" {
  family                   = local.name_prefix
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.app_task.arn
  task_role_arn            = aws_iam_role.app_task.arn

  container_definitions = jsonencode(concat(
    [
      # --- Application Container ---
      {
        name      = var.service_name
        image     = var.container_image
        essential = true

        portMappings = [{
          containerPort = var.container_port
          protocol      = "tcp"
        }]

        environment = [
          { name = "OTEL_SERVICE_NAME", value = var.service_name },
          { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = "http://localhost:4317" },
          { name = "OTEL_RESOURCE_ATTRIBUTES", value = "environment=${var.environment},service.namespace=${var.environment}" },
          { name = "OTEL_TRACES_SAMPLER", value = "parentbased_traceidratio" },
          { name = "OTEL_TRACES_SAMPLER_ARG", value = var.environment == "prod" ? "0.1" : "1.0" },
        ]

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.app.name
            "awslogs-region"        = data.aws_region.current.name
            "awslogs-stream-prefix" = "app"
          }
        }
      }
    ],
    # --- OTel Collector Sidecar (forwards to gateway) ---
    var.enable_auto_instrumentation ? [
      {
        name      = "otel-sidecar"
        image     = "otel/opentelemetry-collector-contrib:0.100.0"
        essential = false

        command = ["--config=/etc/otel/sidecar-config.yaml"]

        portMappings = [
          { containerPort = 4317, protocol = "tcp" },
          { containerPort = 4318, protocol = "tcp" },
        ]

        environment = [
          { name = "OTEL_GATEWAY_ENDPOINT", value = var.otel_collector_endpoint },
        ]

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.app.name
            "awslogs-region"        = data.aws_region.current.name
            "awslogs-stream-prefix" = "otel-sidecar"
          }
        }
      }
    ] : []
  ))

  tags = local.common_tags
}

# =============================================================================
# SECURITY GROUP
# =============================================================================

resource "aws_security_group" "app" {
  name_prefix = "${local.name_prefix}-"
  vpc_id      = var.vpc_id
  description = "Security group for ${var.service_name}"

  ingress {
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "Application port"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# =============================================================================
# ECS SERVICE
# =============================================================================

resource "aws_ecs_service" "app" {
  name            = local.name_prefix
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  tags = local.common_tags
}

# =============================================================================
# VARIABLES (additional)
# =============================================================================

variable "cluster_id" {
  description = "ECS cluster ID to deploy into"
  type        = string
}

# =============================================================================
# DATA SOURCES
# =============================================================================

data "aws_region" "current" {}

# =============================================================================
# OUTPUTS
# =============================================================================

output "service_name" {
  value = aws_ecs_service.app.name
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.app.arn
}

output "security_group_id" {
  value = aws_security_group.app.id
}
