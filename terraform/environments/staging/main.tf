# =============================================================================
# Enterprise Observability Adoption Framework
# Environment: Staging
#
# Phase 2 adoption: Infrastructure Metrics + APM Traces
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

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-west-2"
}

variable "backend_type" {
  description = "Observability backend type"
  type        = string
  default     = "splunk"
}

variable "backend_endpoint" {
  description = "Observability backend endpoint URL"
  type        = string
}

variable "backend_token_arn" {
  description = "ARN of the Secrets Manager secret containing the backend API token"
  type        = string
}

# --- Networking ---
module "networking" {
  source      = "../../modules/networking"
  environment = "staging"
  vpc_cidr    = "10.101.0.0/16"
}

# --- OTel Collector Gateway ---
module "otel_collector" {
  source      = "../../modules/otel-collector"
  environment = "staging"
  vpc_id      = module.networking.vpc_id
  subnet_ids  = module.networking.private_subnet_ids

  desired_count = 2
  cpu           = 1024
  memory        = 2048

  # Phase 2: Infrastructure metrics + APM traces
  enable_infrastructure_metrics = true
  enable_apm_traces             = true
  enable_rum_receiver           = false

  observability_backend = {
    type      = var.backend_type
    endpoint  = var.backend_endpoint
    token_arn = var.backend_token_arn
  }

  tags = {
    Project = "observability-adoption-framework"
    Phase   = "2-application-visibility"
  }
}

output "collector_endpoints" {
  value = module.otel_collector.collector_endpoints
}

output "active_pipelines" {
  value = module.otel_collector.active_pipelines
}
