# =============================================================================
# Enterprise Observability Adoption Framework
# Environment: Production
#
# Phase 4 adoption: Full-stack observability (Infrastructure + APM + RUM)
# High availability with multi-AZ deployment and aggressive auto-scaling.
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
  source             = "../../modules/networking"
  environment        = "prod"
  vpc_cidr           = "10.102.0.0/16"
  availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

# --- OTel Collector Gateway ---
module "otel_collector" {
  source      = "../../modules/otel-collector"
  environment = "prod"
  vpc_id      = module.networking.vpc_id
  subnet_ids  = module.networking.private_subnet_ids

  desired_count = 4
  cpu           = 2048
  memory        = 4096

  # Phase 4: Full-stack observability (all pipelines active)
  enable_infrastructure_metrics = true
  enable_apm_traces             = true
  enable_rum_receiver           = true

  observability_backend = {
    type      = var.backend_type
    endpoint  = var.backend_endpoint
    token_arn = var.backend_token_arn
  }

  tags = {
    Project     = "observability-adoption-framework"
    Phase       = "4-operational-excellence"
    CostCenter  = "observability"
    Criticality = "high"
  }
}

output "collector_endpoints" {
  value = module.otel_collector.collector_endpoints
}

output "active_pipelines" {
  value = module.otel_collector.active_pipelines
}
