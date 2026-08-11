# Quickstart

## 1. Start the stack

```bash
cd ~/Developer/claude-code-telemetry
docker compose up -d
```

Five containers come up: `cc-otel-collector`, `cc-prometheus`, `cc-loki`, `cc-grafana`, `cc-docs`.

Check them:

```bash
docker compose ps
```

## 2. Point Claude Code at it

=== "Try it for one session"

    ```bash
    source ./claude-telemetry.env
    claude
    ```

    The variables only live in that shell. Close it and telemetry stops.

=== "Turn it on permanently"

    Add an `env` block to `~/.claude/settings.json`:

    ```json
    {
      "env": {
        "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
        "OTEL_METRICS_EXPORTER": "otlp",
        "OTEL_LOGS_EXPORTER": "otlp",
        "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
        "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4317",
        "OTEL_METRIC_EXPORT_INTERVAL": "10000",
        "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE": "cumulative",
        "OTEL_METRICS_INCLUDE_VERSION": "true"
      }
    }
    ```

    Every Claude Code session on this machine now reports. If the collector isn't running,
    Claude Code carries on normally — the export just fails quietly in the background.

## 3. Generate some data

Use Claude Code normally, or force a quick sample:

```bash
source ./claude-telemetry.env
claude -p "Reply with exactly: pong"
```

## 4. Look at it

Open **<http://localhost:3000>** — Grafana is set to anonymous admin, so there's no login. The
*Claude Code — Usage & Cost* dashboard is already provisioned.

Give it about 25 seconds after your first session: 10s for the export interval, 15s for the
Prometheus scrape.

## 5. Confirm the chain end to end

If the dashboard is empty, walk the pipeline in order. Each command checks one hop:

```bash
# Hop 1 — is the collector receiving and exposing anything?
curl -s http://localhost:8889/metrics | grep claude_code | head

# Hop 2 — did Prometheus scrape it?
curl -s 'http://localhost:9090/api/v1/label/__name__/values' \
  | python3 -c "import sys,json; print([n for n in json.load(sys.stdin)['data'] if 'claude' in n])"

# Hop 3 — did events reach Loki?
curl -s -G 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service_name="claude-code"}' --data-urlencode 'limit=5' \
  | python3 -m json.tool | head -40
```

The first one that returns nothing is where the problem is. See
[Troubleshooting](troubleshooting.md).

## Stopping

```bash
docker compose stop     # pause, keep data
docker compose down     # remove containers, keep data
docker compose down -v  # remove everything including stored metrics
```
