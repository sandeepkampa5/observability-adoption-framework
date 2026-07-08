# Contributing to the Enterprise Observability Adoption Framework

Thank you for your interest in contributing! This framework is built to be extensible and community-driven.

## How to Contribute

### Adding a New Backend Exporter

1. Create a new file in `otel-configs/exporters/<backend-name>.yaml`
2. Follow the existing exporter pattern (environment variables, pipeline wiring comments)
3. Add the backend to the "Supported Backends" table in `README.md`
4. Test with the Docker Compose example

### Adding Dashboard Schemas

1. Create JSON schemas in the appropriate `dashboards/` subdirectory
2. Follow the schema format in existing dashboards
3. Include `metadata.compatible_backends` listing tested platforms
4. Map to the correct `framework_phase`

### Terraform Modules

1. All modules should support the `environment` variable
2. Use `local.common_tags` pattern for consistent tagging
3. Include outputs for integration with other modules
4. Test with `terraform validate` and `terraform plan`

## Development Setup

```bash
git clone https://github.com/<your-org>/observability-adoption-framework.git
cd observability-adoption-framework
# For local testing:
cd examples/docker-compose && docker-compose up -d
```

## Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/add-backend-xyz`)
3. Make your changes
4. Run `terraform validate` on any Terraform changes
5. Submit a pull request with a clear description

## Code of Conduct

Be respectful, constructive, and collaborative.
