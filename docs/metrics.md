# Metrics reference

## The names you actually query

The left column is what Anthropic's docs call the metric. The right column is the string you type
into Prometheus. **Use the right column.**

| Logical name (docs) | Unit | Prometheus name |
| --- | --- | --- |
| `claude_code.session.count` | none | `claude_code_session_count_total` ✅ |
| `claude_code.token.usage` | tokens | `claude_code_token_usage_tokens_total` ✅ |
| `claude_code.cost.usage` | USD | `claude_code_cost_usage_USD_total` ✅ |
| `claude_code.active_time.total` | s | `claude_code_active_time_seconds_total` ✅ |
| `claude_code.lines_of_code.count` | none | `claude_code_lines_of_code_count_total` |
| `claude_code.commit.count` | none | `claude_code_commit_count_total` |
| `claude_code.pull_request.count` | none | `claude_code_pull_request_count_total` |
| `claude_code.code_edit_tool.decision` | none | `claude_code_code_edit_tool_decision_total` |

✅ = observed directly from this stack. The rest follow the same documented naming rule but only
appear once you trigger them — edit a file, make a commit, approve an edit permission. If a
dashboard panel is empty, check the name against a live list first:

```bash
curl -s http://localhost:8889/metrics | grep -o '^claude_code[a-z_]*' | sort -u
```

Note the capital `USD` in the cost metric. It's a faithful copy of the OTel unit, and it is
case-sensitive.

## Labels on every metric

Captured from a real session:

| Label | Example | Notes |
| --- | --- | --- |
| `session_id` | `5e551011-0000-…` | Unique per session — the cardinality driver |
| `user_email` | `you@example.com` | Present when signed in |
| `user_account_id` | `user_01Example…` | |
| `user_account_uuid` | `aaaaaaaa-…` | |
| `user_id` | `00000000…` (hash) | Anonymous, stable across sessions |
| `organization_id` | `11111111-…` | |
| `app_version` | `2.1.228` | Needs `OTEL_METRICS_INCLUDE_VERSION=true` |
| `app_entrypoint` | `cli`, `sdk-cli` | Needs `OTEL_METRICS_INCLUDE_ENTRYPOINT=true` |
| `terminal_type` | `Apple_Terminal`, `vscode`, `tmux` | Auto-detected |
| `host_name` / `host_arch` | `dev-macbook` / `arm64` | |
| `os_type` / `os_version` | `darwin` / `25.5.0` | |
| `service_name` | `claude-code` | Constant — handy as a catch-all filter |

Underscores, not dots: the collector sanitizes `user.email` → `user_email` for Prometheus.

## Per-metric labels

**`claude_code_token_usage_tokens_total`**

| Label | Values |
| --- | --- |
| `type` | `input`, `output`, `cacheRead`, `cacheCreation` |
| `model` | `claude-haiku-4-5-20251001`, `claude-opus-5`, … |
| `query_source` | `main`, `sdk`, subagent sources |

The `type` split is the one worth internalizing. A session showing 18,267 `cacheRead` against 10
`input` tokens is prompt caching working correctly — cache reads are far cheaper than fresh input,
so a high cache-read ratio is a *good* sign, not a cost problem.

**`claude_code_cost_usage_USD_total`** — `model`, `query_source`

**`claude_code_session_count_total`** — `start_type` (`fresh`, resumed, …)

**`claude_code_lines_of_code_count_total`** — `type` (`added`, `removed`)

**`claude_code_code_edit_tool_decision_total`** — `decision` (`accept`, `reject`), `tool_name`

## Reading these counters correctly

Not the usual Prometheus advice. **Do not use `increase()` or `rate()` on these metrics** — they
return 0.

Each session emits its own series (unique `session_id`) that appears already holding its final
value and then expires shortly after the session ends. `increase()` treats that first sample as
its baseline, so it measures growth from the full value and finds none.

```promql
# ❌ returns 0
sum(increase(claude_code_cost_usage_USD_total[24h]))

# ✅ returns the real total
sum(max_over_time(claude_code_cost_usage_USD_total[24h]))

# ❌ meaningless — an arbitrary snapshot of whichever sessions are still alive
sum(claude_code_cost_usage_USD_total)
```

Summing each series' max works because one series = one session, and its max = that session's
total.

For anything plotted **against time**, use the `api_request` events in Loki instead — they carry
exact per-request cost and latency. Full reasoning and query set in
[Query recipes](queries.md#read-this-first-why-increase-returns-0).
