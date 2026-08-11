# Configuration

Every variable Claude Code reads for telemetry, from the
[official docs](https://code.claude.com/docs/en/monitoring-usage). The ones this stack sets are
marked ✅.

## Core

| Variable | Purpose | Used here |
| --- | --- | --- |
| `CLAUDE_CODE_ENABLE_TELEMETRY` | Master switch. Required — nothing works without it | ✅ `1` |
| `OTEL_METRICS_EXPORTER` | `console`, `otlp`, `prometheus`, `none` | ✅ `otlp` |
| `OTEL_LOGS_EXPORTER` | `console`, `otlp`, `none` | ✅ `otlp` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc`, `http/json`, `http/protobuf` | ✅ `grpc` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Where to send everything | ✅ `http://localhost:4317` |
| `OTEL_EXPORTER_OTLP_HEADERS` | Auth headers, e.g. `Authorization=Bearer x` | — (no auth locally) |
| `OTEL_EXPORTER_OTLP_CLIENT_KEY` | mTLS client key (gRPC) | — |
| `OTEL_EXPORTER_OTLP_CLIENT_CERTIFICATE` | mTLS client cert (gRPC) | — |

### Splitting the destinations

Per-signal overrides beat the general endpoint. Useful if you want metrics local but events
somewhere else:

| Variable | Purpose |
| --- | --- |
| `OTEL_EXPORTER_OTLP_METRICS_PROTOCOL` | Protocol for metrics only |
| `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT` | Endpoint for metrics only |
| `OTEL_EXPORTER_OTLP_LOGS_PROTOCOL` | Protocol for logs only |
| `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` | Endpoint for logs only |

## Timing

| Variable | Default | Notes |
| --- | --- | --- |
| `OTEL_METRIC_EXPORT_INTERVAL` | `60000` ms | ✅ set to `10000`. Your real resolution — see [How it works](how-it-works.md#push-vs-pull-the-one-genuinely-confusing-part) |
| `OTEL_LOGS_EXPORT_INTERVAL` | `5000` ms | ✅ left at default |
| `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` | `delta` | ✅ set to `cumulative` for Prometheus |

!!! tip "Don't set the export interval too low permanently"
    10 seconds is a debugging convenience. Once you trust the setup, raising it back toward 60s
    costs you nothing in accuracy — counters accumulate either way — and cuts the write volume 6×.

## Attributes on metrics

These control cardinality. Each `true` multiplies the number of stored series.

| Variable | Default | Effect |
| --- | --- | --- |
| `OTEL_METRICS_INCLUDE_SESSION_ID` | `true` | Adds `session.id`. **Unique per session** — high cardinality |
| `OTEL_METRICS_INCLUDE_VERSION` | `false` | Adds `app.version`. ✅ enabled — useful for spotting regressions across upgrades |
| `OTEL_METRICS_INCLUDE_ACCOUNT_UUID` | `true` | Adds `user.account_uuid` and `user.account_id` |
| `OTEL_METRICS_INCLUDE_ENTRYPOINT` | `false` | Adds `app.entrypoint` (`cli`, `sdk-cli`, `sdk-ts`, …). ✅ enabled |
| `OTEL_METRICS_INCLUDE_RESOURCE_ATTRIBUTES` | `true` | Honours your `OTEL_RESOURCE_ATTRIBUTES` |

`OTEL_RESOURCE_ATTRIBUTES` is a free-form comma-separated list for slicing your own way:

```bash
export OTEL_RESOURCE_ATTRIBUTES="team=platform,machine=laptop,project=api-rewrite"
```

## Content logging

**Off by default. All of it writes your actual text into Loki in plaintext.** Read
[Privacy](privacy.md) before enabling any of these.

| Variable | What it captures |
| --- | --- |
| `OTEL_LOG_USER_PROMPTS` | The prompts you type |
| `OTEL_LOG_ASSISTANT_RESPONSES` | Claude's response text |
| `OTEL_LOG_TOOL_DETAILS` | Tool parameters and input arguments |
| `OTEL_LOG_TOOL_CONTENT` | Tool input/output content in spans |
| `OTEL_LOG_RAW_API_BODIES` | Full request/response JSON. `1` inline, or `file:<dir>` to disk |
| `CLAUDE_CODE_OTEL_CONTENT_MAX_LENGTH` | Truncation limit, default `61440` UTF-16 units |

## Tracing (beta)

Spans, not just counters — the timing breakdown within a request. Not wired into this stack; you'd
need Tempo or Jaeger as a fourth backend.

| Variable | Purpose |
| --- | --- |
| `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA` | Required to emit spans at all |
| `OTEL_TRACES_EXPORTER` | `console`, `otlp`, `none` |
| `OTEL_EXPORTER_OTLP_TRACES_PROTOCOL` | Protocol for traces |
| `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | Endpoint for traces |
| `OTEL_TRACES_EXPORT_INTERVAL` | Batch interval, default `5000` ms |
| `CLAUDE_CODE_PROPAGATE_TRACEPARENT` | Propagate W3C trace context to proxies |

## Auth for real deployments

Local needs none. Pointed at a hosted backend, you'd add:

```bash
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Bearer $TOKEN"
```

For tokens that expire, Claude Code supports a helper script in `.claude/settings.json`:

```json
{ "otelHeadersHelper": "/path/to/generate-otel-headers.sh" }
```

```bash
#!/bin/bash
echo "{\"Authorization\": \"Bearer $(get-token.sh)\"}"
```

Refresh cadence is `CLAUDE_CODE_OTEL_HEADERS_HELPER_DEBOUNCE_MS` (default 1740000 ms ≈ 29 min).

## Changing the stack itself

| File | Controls |
| --- | --- |
| `docker-compose.yml` | Services, ports, volumes, retention flags |
| `otel-collector-config.yaml` | Receivers, processors, exporters, pipelines |
| `prometheus.yml` | Scrape interval and targets |
| `loki-config.yaml` | Storage, retention, which attributes get indexed |
| `grafana/provisioning/` | Datasources and dashboard auto-loading |
| `grafana/dashboards/` | Dashboard JSON — edited here, or in the UI then exported |

After editing a config, restart just that service:

```bash
docker compose restart otel-collector
```
