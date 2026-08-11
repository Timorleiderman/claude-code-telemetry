# Query recipes

Paste these into Grafana's **Explore** view (left sidebar) — pick the Prometheus datasource for
PromQL, Loki for LogQL.

## Read this first: why `increase()` returns 0

This is the one non-obvious thing about Claude Code metrics, and it will waste an afternoon if
nobody tells you.

Every session emits its **own counter series**, tagged with a unique `session_id`. That series:

1. appears for the first time *already holding its final value* (one export carries the whole
   session's cumulative total), then
2. stops updating and expires a few minutes after the session ends.

Prometheus's `increase()` and `rate()` treat the first sample of a series as their **baseline** —
the thing to measure growth *from*. A series that is born at `$0.018` and never moves has grown by
nothing, so:

```promql
sum(increase(claude_code_cost_usage_USD_total[24h]))   # → 0    ❌
```

Sum the **maximum** of each series instead. Each series' max is that session's total, and summing
across sessions gives the real number:

```promql
sum(max_over_time(claude_code_cost_usage_USD_total[24h]))   # → 0.0284   ✅
```

!!! note "The trade-off"
    `max_over_time` counts a session's *entire* total if any part of it falls inside your time
    range, so a long session straddling the boundary is attributed wholly to that window. For a
    personal usage dashboard that's a fine price for numbers that aren't zero. When you need
    precise time attribution, use the event-based queries further down — they're exact.

## Totals (PromQL)

```promql
# Total spend
sum(max_over_time(claude_code_cost_usage_USD_total[$__range]))

# Spend per model
sum by (model) (max_over_time(claude_code_cost_usage_USD_total[$__range]))

# Most expensive sessions
topk(5, sum by (session_id) (max_over_time(claude_code_cost_usage_USD_total[$__range])))

# Tokens by type
sum by (type) (max_over_time(claude_code_token_usage_tokens_total[$__range]))

# Sessions started
sum(max_over_time(claude_code_session_count_total[$__range]))

# Active hours
sum(max_over_time(claude_code_active_time_seconds_total[$__range])) / 3600

# Which terminal you actually work in
sum by (terminal_type) (max_over_time(claude_code_session_count_total[$__range]))

# Code churn, once Claude has edited files
sum by (type) (max_over_time(claude_code_lines_of_code_count_total[$__range]))
```

### Cache efficiency

A high cache-read share is good — cached tokens cost a fraction of fresh input:

```promql
sum(max_over_time(claude_code_token_usage_tokens_total{type="cacheRead"}[$__range]))
  /
sum(max_over_time(claude_code_token_usage_tokens_total{type=~"cacheRead|input"}[$__range]))
```

### Cost per 1k output tokens

```promql
sum(max_over_time(claude_code_cost_usage_USD_total[$__range]))
  /
(sum(max_over_time(claude_code_token_usage_tokens_total{type="output"}[$__range])) / 1000)
```

## Over time (LogQL)

For anything plotted against time, query the **events** rather than the metrics. Each
`api_request` event is one request with its own `cost_usd`, `duration_ms` and token counts, so
aggregating them is exact — no counter semantics involved.

`unwrap` is the key: it pulls a numeric attribute out of an event so it can be aggregated.

```logql
# Cost per interval, by model
sum by (model) (sum_over_time({event_name="api_request"} | unwrap cost_usd [$__interval]))

# p95 latency by model
quantile_over_time(0.95, {event_name="api_request"} | unwrap duration_ms [$__interval]) by (model)

# Requests per interval
sum by (model) (count_over_time({event_name="api_request"}[$__interval]))

# Output tokens per interval
sum(sum_over_time({event_name="api_request"} | unwrap output_tokens [$__interval]))

# Cache reads per interval
sum(sum_over_time({event_name="api_request"} | unwrap cache_read_tokens [$__interval]))
```

Outside a Grafana panel, replace `$__interval` with a literal window like `[5m]`.

## Browsing events (LogQL)

```logql
# Everything, newest first
{service_name="claude-code"}

# Just API calls
{event_name="api_request"}

# Errors and refusals
{event_name=~"api_error|api_refusal|internal_error"}

# One prompt's full fan-out — often many calls
{event_name="api_request"} | prompt_id="<paste-a-prompt-id>"

# Slow calls
{event_name="api_request"} | duration_ms > 5000

# Expensive individual calls
{event_name="api_request"} | cost_usd > 0.05

# Rejected tool permissions
{event_name="tool_decision"} | decision="reject"
```

Only `service_name`, `service_version`, `host_name`, `os_type` and `event_name` may appear inside
`{}` — they're the indexed labels. Everything else is structured metadata, filtered after a `|`.

## Gotchas

**Empty result?** Widen the time range. It's the cause about half the time.

**Zero result?** You used `increase()` or `rate()`. See the top of this page.

**Case matters.** `claude_code_cost_usage_USD_total` — capital `USD`.

**Metrics and events can disagree** on totals if you changed `loki-config.yaml` after collecting
data. Records ingested under different attribute-indexing rules aren't directly comparable;
`docker compose down -v` gives you a clean slate.
