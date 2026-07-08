"""
Enterprise Observability Adoption Framework - Architecture Diagram

Generates a comprehensive architecture diagram showing the pluggable,
backend-agnostic observability gateway pattern.

Author: Sandeep Kampa
Attribution: Based on architecture from Splunk Tech Talks (2023-2024)

Requirements: pip install diagrams
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import ECS, Fargate
from diagrams.aws.network import VPC, ALB, Route53
from diagrams.aws.management import Cloudwatch
from diagrams.aws.security import SecretsManager
from diagrams.aws.integration import Eventbridge
from diagrams.onprem.monitoring import Grafana, Prometheus, Datadog
from diagrams.onprem.tracing import Jaeger
from diagrams.onprem.client import Users, Client
from diagrams.onprem.container import Docker
from diagrams.onprem.compute import Server
from diagrams.programming.framework import React
from diagrams.generic.database import SQL
from diagrams.generic.network import Firewall
from diagrams.custom import Custom

graph_attrs = {
    "fontsize": "28",
    "bgcolor": "white",
    "pad": "0.5",
    "nodesep": "0.8",
    "ranksep": "1.2",
}

with Diagram(
    "Enterprise Observability Adoption Framework",
    filename="/Users/sankampa/Myrepos/observability-adoption-framework/docs/architecture/framework-architecture",
    show=False,
    direction="TB",
    graph_attr=graph_attrs,
):

    # === User Layer ===
    with Cluster("End Users & Applications", graph_attr={"style": "dashed", "color": "#2196F3", "fontcolor": "#2196F3"}):
        users = Users("Browser Users\n(RUM Telemetry)")
        mobile = Client("Mobile Apps")
        
        with Cluster("Microservices (Auto-Instrumented)", graph_attr={"bgcolor": "#E3F2FD"}):
            svc_a = Server("Service A\n(OTel SDK)")
            svc_b = Server("Service B\n(OTel SDK)")
            svc_c = Server("Service C\n(OTel SDK)")
            db = SQL("Databases")

    # === Collector Gateway ===
    with Cluster("OpenTelemetry Collector Gateway (ECS Fargate)", graph_attr={"style": "rounded", "color": "#4CAF50", "bgcolor": "#E8F5E9", "fontcolor": "#2E7D32"}):
        
        with Cluster("Receivers", graph_attr={"bgcolor": "#C8E6C9"}):
            otlp = Firewall("OTLP\ngRPC/HTTP")
            jaeger_recv = Firewall("Jaeger")
            zipkin_recv = Firewall("Zipkin")
            prom_recv = Firewall("Prometheus\nScrape")

        with Cluster("Processors", graph_attr={"bgcolor": "#A5D6A7"}):
            batch = Docker("Batch &\nMemory Limit")
            enrich = Docker("Resource\nDetection &\nK8s Attrs")
            sample = Docker("Tail\nSampling")
            filter_p = Docker("Filter &\nTransform")

    # === Pluggable Exporters ===
    with Cluster("Pluggable Backend Exporters (Swap YAML)", graph_attr={"style": "rounded,dashed", "color": "#FF9800", "bgcolor": "#FFF3E0", "fontcolor": "#E65100"}):
        splunk_exp = Datadog("Splunk\nObservability")
        dd_exp = Datadog("Datadog")
        grafana_exp = Grafana("Grafana Cloud\n(Tempo/Mimir/Loki)")
        nr_exp = Prometheus("New Relic")
        aws_exp = Cloudwatch("AWS\nCloudWatch/X-Ray")
        elastic_exp = Jaeger("Elastic\nAPM")
        oss_exp = Prometheus("Self-Hosted\n(Jaeger+Prom)")

    # === Dashboards ===
    with Cluster("Unified Dashboards (Phase 1→4)", graph_attr={"style": "rounded", "color": "#9C27B0", "bgcolor": "#F3E5F5", "fontcolor": "#6A1B9A"}):
        rum_dash = Grafana("RUM\nCore Web Vitals")
        apm_dash = Grafana("APM\nService Health")
        infra_dash = Grafana("Infrastructure\nHost Overview")
        unified_dash = Grafana("Unified\nService Health")

    # === Infrastructure ===
    with Cluster("AWS Infrastructure (Terraform)", graph_attr={"style": "dashed", "color": "#607D8B"}):
        vpc = VPC("VPC")
        ecs = ECS("ECS Cluster")
        fargate = Fargate("Fargate Tasks\n(Auto-Scaling)")
        secrets = SecretsManager("Secrets\n(API Tokens)")
        alb = ALB("Internal ALB")

    # === Connections ===

    # Users → Collector
    users >> Edge(label="Web Vitals, Errors", color="#2196F3", style="bold") >> otlp
    mobile >> Edge(color="#2196F3") >> otlp

    # Services → Collector
    svc_a >> Edge(label="Traces + Metrics", color="#4CAF50") >> otlp
    svc_b >> Edge(color="#4CAF50") >> otlp
    svc_c >> Edge(color="#4CAF50") >> jaeger_recv
    svc_a >> Edge(color="#666666", style="dashed") >> db
    svc_b >> Edge(color="#666666", style="dashed") >> db

    # Receivers → Processors
    otlp >> Edge(color="#388E3C") >> batch
    jaeger_recv >> Edge(color="#388E3C") >> batch
    zipkin_recv >> Edge(color="#388E3C") >> batch
    prom_recv >> Edge(color="#388E3C") >> batch
    
    batch >> Edge(color="#388E3C") >> enrich
    enrich >> Edge(color="#388E3C") >> sample
    sample >> Edge(color="#388E3C") >> filter_p

    # Processors → Exporters (fan-out)
    filter_p >> Edge(label="Traces", color="#FF9800") >> splunk_exp
    filter_p >> Edge(color="#FF9800") >> dd_exp
    filter_p >> Edge(color="#FF9800") >> grafana_exp
    filter_p >> Edge(color="#FF9800") >> nr_exp
    filter_p >> Edge(label="Metrics + Logs", color="#FF9800") >> aws_exp
    filter_p >> Edge(color="#FF9800") >> elastic_exp
    filter_p >> Edge(color="#FF9800") >> oss_exp

    # Backends → Dashboards
    splunk_exp >> Edge(color="#9C27B0", style="dashed") >> rum_dash
    grafana_exp >> Edge(color="#9C27B0", style="dashed") >> apm_dash
    aws_exp >> Edge(color="#9C27B0", style="dashed") >> infra_dash
    dd_exp >> Edge(color="#9C27B0", style="dashed") >> unified_dash

    # Infrastructure connections
    alb >> Edge(color="#607D8B") >> fargate
    fargate >> Edge(color="#607D8B") >> secrets
