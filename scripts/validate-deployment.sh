#!/usr/bin/env bash
# =============================================================================
# Enterprise Observability Adoption Framework
# Deployment Validation Script
#
# Validates that the OTel Collector is healthy and receiving telemetry.
#
# Usage: ./validate-deployment.sh <collector-endpoint>
# Example: ./validate-deployment.sh http://localhost:13133
# =============================================================================

set -euo pipefail

COLLECTOR_ENDPOINT="${1:-http://localhost:13133}"
METRICS_ENDPOINT="${COLLECTOR_ENDPOINT%:*}:8888/metrics"

echo "============================================"
echo "  Observability Framework - Deploy Validator"
echo "============================================"
echo ""

# --- Health Check ---
echo "1. Health Check: ${COLLECTOR_ENDPOINT}"
if curl -sf "${COLLECTOR_ENDPOINT}/" > /dev/null 2>&1; then
  echo "   ✅ Collector is healthy"
else
  echo "   ❌ Collector is NOT responding"
  exit 1
fi
echo ""

# --- Metrics Check ---
echo "2. Self-Metrics: ${METRICS_ENDPOINT}"
if curl -sf "${METRICS_ENDPOINT}" > /dev/null 2>&1; then
  RECEIVERS=$(curl -sf "${METRICS_ENDPOINT}" | grep -c "otelcol_receiver_accepted" || echo "0")
  EXPORTERS=$(curl -sf "${METRICS_ENDPOINT}" | grep -c "otelcol_exporter_sent" || echo "0")
  echo "   ✅ Metrics endpoint responding"
  echo "   📊 Receiver metric lines: ${RECEIVERS}"
  echo "   📊 Exporter metric lines: ${EXPORTERS}"
else
  echo "   ⚠️  Metrics endpoint not available (non-critical)"
fi
echo ""

# --- Port Checks ---
echo "3. Receiver Ports:"
COLLECTOR_HOST="${COLLECTOR_ENDPOINT#http://}"
COLLECTOR_HOST="${COLLECTOR_HOST%:*}"

for port in 4317 4318 14250 9411; do
  if nc -z "${COLLECTOR_HOST}" "${port}" 2>/dev/null; then
    echo "   ✅ Port ${port} open"
  else
    echo "   ⚠️  Port ${port} closed (receiver may be disabled)"
  fi
done
echo ""

echo "============================================"
echo "  Validation complete!"
echo "============================================"
