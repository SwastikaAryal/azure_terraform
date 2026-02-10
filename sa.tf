Update Observability Pipeline: Send Logs to Loki, Traces to Jaeger, and Metrics to Prometheus
Description (Points)

Current observability setup is not fully aligned with the target monitoring stack

Logs, traces, and metrics need to be routed to the correct tools

Update telemetry/export configuration so that:

Logs are sent to Loki

Traces are sent to Jaeger (instead of Azure Application Insights)

Metrics are exposed and collected by Prometheus

Replace the existing trace exporter integration with Jaeger exporter

Ensure all telemetry data is successfully ingested and visible in the respective platforms

Validate end-to-end observability pipeline with no data loss

Document configuration and deployment changes for future maintenance

Acceptance Criteria

 Application logs are successfully visible in Loki with correct labels and filtering

 Traces are no longer sent to Application Insights

 Traces are successfully exported and searchable in Jaeger

 Application metrics are available in Prometheus and can be queried

 No major telemetry gaps or performance degradation observed after migration

 Configuration changes are documented for future reference
