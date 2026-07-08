# Adoption Playbook

## Overview

This playbook implements the **phased, maturity-driven adoption approach** that achieved:
- 82% knowledge improvement in attendee surveys
- 48% adoption intent within 30 days
- 50% faster page load times
- 85% faster problem detection and resolution
- 90% reduction in war room attendees

## Phase 1: Foundation (Weeks 1-4)

**Goal**: Establish infrastructure visibility baseline

### Steps:
1. Deploy OTel Collector Gateway using Terraform
2. Enable `hostmetrics` and `docker_stats` receivers
3. Configure your backend exporter (see `otel-configs/exporters/`)
4. Deploy the Infrastructure dashboard (`dashboards/infrastructure/host-overview.json`)
5. Set critical alerts: CPU > 95%, Memory > 95%, Disk > 90%

### Success Criteria:
- All hosts reporting metrics
- Dashboard showing fleet overview
- Alerts firing correctly on threshold breaches

---

## Phase 2: Application Visibility (Weeks 5-8)

**Goal**: Enable distributed tracing and service dependency mapping

### Steps:
1. Enable `traces` pipeline in collector config
2. Auto-instrument application services with OTel SDKs
3. Deploy APM dashboard (`dashboards/apm/service-health.json`)
4. Configure tail sampling for cost optimization
5. Create service dependency map

### Success Criteria:
- Service map showing all inter-service communication
- End-to-end traces from entry point to database
- Latency percentiles (p50/p90/p99) visible per endpoint

---

## Phase 3: User Experience (Weeks 9-12)

**Goal**: Correlate user impact with backend behavior

### Steps:
1. Deploy RUM instrumentation (browser SDK)
2. Enable RUM receiver in collector
3. Deploy Core Web Vitals dashboard (`dashboards/rum/core-web-vitals.json`)
4. Create user journey → trace → infrastructure correlation

### Success Criteria:
- Core Web Vitals tracked for all key pages
- Able to trace: slow LCP → backend API call → database query → host CPU
- Geographic performance distribution visible

---

## Phase 4: Operational Excellence (Ongoing)

**Goal**: Automated incident correlation and performance optimization

### Steps:
1. Deploy unified Service Health dashboard (`dashboards/service-health/unified-overview.json`)
2. Configure cross-signal alerting (RUM + APM + Infra)
3. Implement deployment markers for change correlation
4. Establish performance budgets and SLO tracking

### Success Criteria:
- Mean Time to Detect (MTTD) reduced by 85%
- Incidents resolved in minutes, not hours
- War room attendees reduced by 90%
- Continuous Core Web Vitals improvement

---

## Architecture Patterns

### Transaction-Level Visibility
```
User Click → Browser (RUM) → API Gateway → Service A → Service B → Database
    │              │              │              │            │          │
    └── LCP ───────┘              │              │            │          │
                                  └── Trace Span ┘            │          │
                                                              └── DB Query Duration
```

### Service-Aware Infrastructure
Instead of alerting on raw CPU %, correlate with the service running on that host:
- Host CPU > 85% AND service.error_rate > 1% → **Actionable alert**
- Host CPU > 85% AND service.error_rate = 0% → **Informational only**

---

## Reference

- [Adoption of RUM and APM at Splunk](https://discover.splunk.com/Adoption-of-RUM-and-APM-at-Splunk.html)
- [YouTube: .conf2023 Observability Demo](https://www.youtube.com/watch?v=P2UdO9Rb28U)
- [Splunk Community: Observability Tech Talks](https://community.splunk.com/t5/tag/observability/tg-p/board-id/splunktechtalks)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
