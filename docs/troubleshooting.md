# Troubleshooting

## Walk the pipeline in order

Data flows Claude Code → collector → Prometheus/Loki → Grafana. Test each hop; the first failure
is your answer.

```bash
# 0. Are the containers up?
docker compose ps

# 1. Is the collector healthy?
docker compose logs otel-collector --tail 30

# 2. Is it receiving and exposing metrics?
curl -s http://localhost:8889/metrics | grep claude_code | head

# 3. Did Prometheus scrape successfully?
curl -s http://localhost:9090/api/v1/targets \
  | python3 -c "import sys,json; [print(t['scrapeUrl'], t['health'], t.get('lastError','')) for t in json.load(sys.stdin)['data']['activeTargets']]"

# 4. Did events reach Loki?
curl -s -G 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service_name="claude-code"}' --data-urlencode 'limit=5' \
  | python3 -m json.tool | head -30
```

## Nothing anywhere

**Did you actually enable it?** In a Claude Code session:

```bash
echo $CLAUDE_CODE_ENABLE_TELEMETRY   # must print 1
echo $OTEL_EXPORTER_OTLP_ENDPOINT    # must print http://localhost:4317
```

Empty means you didn't `source ./claude-telemetry.env`, or you added it to `~/.claude/settings.json`
but haven't restarted Claude Code since.

**Env vars don't reach existing sessions.** They're read at startup. Restart Claude Code.

**Bypass the whole stack to isolate the problem.** If this prints metrics, Claude Code is fine and
the issue is on the Docker side:

```bash
CLAUDE_CODE_ENABLE_TELEMETRY=1 OTEL_METRICS_EXPORTER=console \
OTEL_METRIC_EXPORT_INTERVAL=1000 claude -p "hi"
```

## Metrics missing but events work (or vice versa)

They're separate pipelines with separate switches. You need **both**:

```bash
export OTEL_METRICS_EXPORTER=otlp   # metrics → Prometheus
export OTEL_LOGS_EXPORTER=otlp      # events  → Loki
```

## "It's been 5 seconds and nothing's there"

Latency is stacked and expected:

- up to 10s — Claude Code's export interval
- up to 15s — Prometheus scrape interval
- plus Grafana's own refresh

**Wait ~30 seconds** after a session before concluding anything is broken.

## Panels show 0 even though data exists

You're using `increase()` or `rate()`. On Claude Code's per-session counters they return 0 by
design — the series is born at its final value, so there's no growth to measure.

```promql
sum(max_over_time(claude_code_cost_usage_USD_total[24h]))   # use this instead
```

Full explanation in [Query recipes](queries.md#read-this-first-why-increase-returns-0).

## Dashboard panel is empty but the metric exists

Almost always the metric name. The exporter appends the unit, so the docs' `claude_code.token.usage`
is really `claude_code_token_usage_tokens_total`. Get the live list:

```bash
curl -s http://localhost:8889/metrics | grep -o '^claude_code[a-z_]*' | sort -u
```

Also check: is your time range wide enough, and are you wrapping the counter in `increase()`?

Panels for `lines_of_code`, `commit`, `pull_request` and `code_edit_tool_decision` stay empty until
you do the corresponding thing — those metrics aren't emitted until Claude edits a file, commits,
or asks for edit permission.

## Port already in use

```
Error starting userland proxy: listen tcp4 127.0.0.1:3000: bind: address already in use
```

Something else owns the port. Find it, or remap the left-hand side in `docker-compose.yml`
(`"127.0.0.1:3001:3000"`):

```bash
lsof -nP -iTCP:3000 -sTCP:LISTEN
```

## Collector won't start after a config edit

YAML is unforgiving about indentation. The logs name the offending key:

```bash
docker compose logs otel-collector --tail 40
```

Component names changed in recent collector versions — `otlphttp` → `otlp_http`,
`deltatocumulative` → `delta_to_cumulative`. The old names still work but log a deprecation
warning; this repo uses the new ones.

## Loki rejects events

```bash
docker compose logs loki --tail 40
```

If you see errors about structured metadata, confirm `allow_structured_metadata: true` is set in
`loki-config.yaml` — OTLP ingestion depends on it.

## Loki looks like it's indexing everything

A `query_range` response lists every attribute inside `stream`, which suggests the cardinality
limits in `loki-config.yaml` did nothing. They almost certainly worked — the query API merges
structured metadata into that object for display. Check the real index:

```bash
curl -s http://localhost:3100/loki/api/v1/labels | python3 -m json.tool
```

Expect five: `event_name`, `host_name`, `os_type`, `service_name`, `service_version`.

## Grafana shows "datasource not found"

Provisioning runs at startup and the datasource UIDs (`prometheus`, `loki`) are referenced by the
dashboard JSON. If you edited either, restart:

```bash
docker compose restart grafana
```

## Start completely fresh

```bash
docker compose down -v
docker compose up -d
```

`-v` deletes the data volumes. Everything collected so far is gone.

## Does telemetry break Claude Code if the collector is down?

No. Exports fail silently in the background and the CLI works normally. You can leave the env vars
in `~/.claude/settings.json` permanently and only start the Docker stack when you want to look at
something.
