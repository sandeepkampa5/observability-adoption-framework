# =============================================================================
# Quick Start Example: Deploy Full Observability Stack
#
# This example shows how to wire all modules together for a complete
# deployment with a sample application.
# =============================================================================

module "networking" {
  source      = "../modules/networking"
  environment = "dev"
  vpc_cidr    = "10.200.0.0/16"
}

module "backend" {
  source       = "../modules/observability-backend"
  environment  = "dev"
  backend_type = "grafana"  # Change to: splunk, datadog, newrelic, aws, elastic, oss
  api_token    = var.backend_api_token

  backend_config = {
    endpoint = "https://otlp-gateway-prod-us-east-0.grafana.net/otlp"
  }
}

module "otel_collector" {
  source      = "../modules/otel-collector"
  environment = "dev"
  vpc_id      = module.networking.vpc_id
  subnet_ids  = module.networking.private_subnet_ids

  enable_infrastructure_metrics = true
  enable_apm_traces             = true
  enable_rum_receiver           = true

  observability_backend = module.backend.collector_backend_config
}

module "sample_app" {
  source          = "../modules/compute"
  environment     = "demo"
  vpc_id          = module.networking.vpc_id
  subnet_ids      = module.networking.private_subnet_ids
  cluster_id      = module.otel_collector.cluster_id
  service_name    = "sample-api"
  container_image = "ghcr.io/open-telemetry/demo:latest"
  container_port  = 8080
  otel_sdk_language           = "java"
  otel_collector_endpoint     = module.otel_collector.collector_endpoints.otlp_grpc
  enable_auto_instrumentation = true
}

variable "backend_api_token" {
  type      = string
  sensitive = true
}
