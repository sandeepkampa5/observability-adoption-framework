# =============================================================================
# Enterprise Observability Adoption Framework
# Terraform Module: Observability Backend Integration
#
# Creates the backend-specific resources needed to connect the OTel Collector
# to your chosen observability platform. This is the "pluggable" layer —
# swap this module's configuration to change backends.
#
# Supported backends: splunk, datadog, grafana, newrelic, aws, elastic, oss
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
  description = "Deployment environment"
  type        = string
}

variable "backend_type" {
  description = "Observability backend type"
  type        = string
  validation {
    condition     = contains(["splunk", "datadog", "grafana", "newrelic", "aws", "elastic", "oss"], var.backend_type)
    error_message = "Supported backends: splunk, datadog, grafana, newrelic, aws, elastic, oss."
  }
}

variable "api_token" {
  description = "API token for the observability backend (stored in Secrets Manager)"
  type        = string
  sensitive   = true
}

variable "backend_config" {
  description = "Backend-specific configuration"
  type = object({
    endpoint = optional(string, "")
    realm    = optional(string, "")   # Splunk realm (us0, us1, eu0)
    site     = optional(string, "")   # Datadog site (datadoghq.com, datadoghq.eu)
    region   = optional(string, "")   # AWS region or backend region
  })
  default = {}
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
    Backend     = var.backend_type
    ManagedBy   = "terraform"
  })

  # Resolve the backend endpoint based on type
  backend_endpoints = {
    splunk  = "https://ingest.${var.backend_config.realm}.signalfx.com"
    datadog = "https://api.${var.backend_config.site}"
    grafana = var.backend_config.endpoint
    newrelic = "otlp.nr-data.net:4317"
    aws     = "https://xray.${var.backend_config.region}.amazonaws.com"
    elastic = var.backend_config.endpoint
    oss     = var.backend_config.endpoint
  }

  resolved_endpoint = local.backend_endpoints[var.backend_type]
}

# =============================================================================
# SECRETS MANAGER - Store API Token
# =============================================================================

resource "aws_secretsmanager_secret" "backend_token" {
  name_prefix = "${local.name_prefix}-${var.backend_type}-token-"
  description = "API token for ${var.backend_type} observability backend"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "backend_token" {
  secret_id     = aws_secretsmanager_secret.backend_token.id
  secret_string = var.api_token
}

# =============================================================================
# IAM POLICY - Backend-specific permissions (AWS backend only)
# =============================================================================

resource "aws_iam_policy" "aws_backend" {
  count       = var.backend_type == "aws" ? 1 : 0
  name_prefix = "${local.name_prefix}-aws-o11y-"
  description = "Permissions for OTel Collector to export to CloudWatch and X-Ray"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/observability/*"
      }
    ]
  })

  tags = local.common_tags
}

# =============================================================================
# CLOUDWATCH LOG GROUP (AWS backend - application logs destination)
# =============================================================================

resource "aws_cloudwatch_log_group" "app_logs" {
  count             = var.backend_type == "aws" ? 1 : 0
  name              = "/observability/${var.environment}/applications"
  retention_in_days = var.environment == "prod" ? 90 : 14

  tags = local.common_tags
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "backend_token_arn" {
  description = "ARN of the secret containing the backend API token"
  value       = aws_secretsmanager_secret.backend_token.arn
}

output "backend_endpoint" {
  description = "Resolved backend endpoint URL"
  value       = local.resolved_endpoint
}

output "backend_type" {
  description = "Configured backend type"
  value       = var.backend_type
}

output "aws_backend_policy_arn" {
  description = "IAM policy ARN for AWS backend (null for other backends)"
  value       = var.backend_type == "aws" ? aws_iam_policy.aws_backend[0].arn : null
}

output "collector_backend_config" {
  description = "Configuration object to pass to the otel-collector module"
  value = {
    type      = var.backend_type
    endpoint  = local.resolved_endpoint
    token_arn = aws_secretsmanager_secret.backend_token.arn
    region    = var.backend_config.region
  }
}
