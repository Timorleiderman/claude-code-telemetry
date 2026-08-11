# Claude Code Telemetry

A self-contained OpenTelemetry stack for monitoring [Claude Code](https://code.claude.com) usage —
tokens, cost, latency, and a searchable log of every API call. Runs entirely on localhost, nothing
leaves your machine.

Claude Code already speaks OpenTelemetry. You just have to give it somewhere to talk to.

```bash
docker compose up -d          # start the stack
source ./claude-telemetry.env # point Claude Code at it
claude
```

- **<http://localhost:3000>** — Grafana dashboard (no login)
- **<http://localhost:8000>** — full documentation

## Why

Claude Code's per-request cost varies by ~100×. The monthly bill won't tell you which sessions,
which prompts, or which habits are responsible. This does.

```
$ ./usage-report -m

  session 5e551011  —  9 messages, $5.8476
  ────────────────────────────────────────────────────────────────────────────
  time      id             cost       cum  req     out  message
  ────────────────────────────────────────────────────────────────────────────
  21:20:01  9r0m9703    $1.2379   $1.2379    3   3,868  <redacted, 61 chars>
  21:31:37  9r0m9705    $1.1243   $3.5525   11   9,179  <redacted, 62 chars>
  21:39:05  9r0m9707    $0.4290   $4.3659    4   3,212  fix the failing auth test
  21:45:27  9r0m9709    $0.3676   $5.8476    3   3,252  make the CLI output easier to scan
  ────────────────────────────────────────────────────────────────────────────
  priciest: $1.2379 at 21:20:01
  drill into any row:  ./usage-report --prompt <id>   (e.g. 9r0m9703)
```

One message is not one API call — the `req` column is the fan-out from tool loops and retries.

Drill into any of them:

```
$ ./usage-report --prompt last

  message 9r0m9704  —  $1.5044 across 11 API calls, 11 tool calls, 195s wall
  ──────────────────────────────────────────────────────────────────────────
   1. 21:50:32  API call     $0.1856    44.9s   out=3,814  cacheRead=179,837
      21:50:40  ✓ Edit       0.0s → 172B        .../usage-report
  ──────────────────────────────────────────────────────────────────────────
   2. 21:50:40  API call     $0.1420     7.9s   out=531    cacheRead=179,866
  ──────────────────────────────────────────────────────────────────────────
   3. 21:50:44  API call     $0.1015     3.6s   out=147    cacheRead=183,741
      21:50:46  ✗ Bash       FAILED 0.6s        git log --oneline | head -20
```

## What's in the box

```
docker-compose.yml           collector, prometheus, loki, grafana, docs
otel-collector-config.yaml   OTLP in → Prometheus + Loki out
prometheus.yml               scrape config
loki-config.yaml             storage, retention, attribute indexing
claude-telemetry.env         the env vars Claude Code needs
grafana/                     provisioned datasource + dashboard
docs/                        MkDocs Material source (served at :8000)

usage-report                 cost/token/latency reports from the terminal
claude-verbose               launch one session with content logging on
tag-sessions.sh              auto-tag sessions by project directory
```

## Three things that will trip you up

Documented properly in `docs/`, but worth knowing up front:

**1. The metric names in Anthropic's docs don't exist in Prometheus.**
`claude_code.token.usage` becomes `claude_code_token_usage_tokens_total` — dots to underscores,
then the exporter appends the OTel unit and `_total`.

**2. `increase()` returns 0.** Each session emits its own counter series that appears *already at
its final value*, so Prometheus treats that first sample as the baseline and measures no growth.
Use `sum(max_over_time(...))` instead. Time-series panels read from Loki events, where per-request
cost is exact.

**3. There is no workspace/cwd attribute.** With several sessions running you cannot tell which is
which out of the box. `tag-sessions.sh` wraps `claude` to tag each session with its directory.

## Privacy

Metadata only by default — your prompts, responses and file contents are **not** recorded
(`prompt: <REDACTED>`). Content logging is opt-in per session via `./claude-verbose`, or globally
via `settings.json`. Every port binds to `127.0.0.1`.

Read `docs/privacy.md` before enabling content logging; it writes plaintext to an unauthenticated
Loki with 90-day retention.

## Docs

The documentation is a MkDocs Material site served by the `docs` container, live-reloading as you
edit `docs/*.md`. Static build:

```bash
docker compose run --rm docs build   # output in site/
```

## License

MIT
