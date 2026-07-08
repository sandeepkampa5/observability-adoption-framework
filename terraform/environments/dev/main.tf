# =============================================================================
# Enterprise Observability Adoption Framework
# Environment: Development
#
# Quick-start deployment for Phase 1 adoption (Infrastructure Metrics)
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
  environment = "dev"
  vpc_cidr    = "10.100.0.0/16"
}

# --- OTel Collector Gateway ---
module "otel_collector" {
  source      = "../../modules/otel-collector"
  environment = "dev"
  vpc_id      = module.networking.vpc_id
  subnet_ids  = module.networking.private_subnet_ids

  desired_count = 1
  cpu           = 512
  memory        = 1024

  # Phase 1: Start with infrastructure metrics
  enable_infrastructure_metrics = true
  enable_apm_traces             = false
  enable_rum_receiver           = false

  observability_backend = {
    type      = var.backend_type
    endpoint  = var.backend_endpoint
    token_arn = var.backend_token_arn
  }

  tags = {
    Project = "observability-adoption-framework"
    Phase   = "1-foundation"
  }
}

output "collector_endpoints" {
  value = module.otel_collector.collector_endpoints
}
