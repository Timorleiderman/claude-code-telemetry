# Claude Code Telemetry

A self-contained OpenTelemetry stack that runs on your Mac and records what Claude Code is doing:
how many tokens you burn, what it costs, which models you use, how long requests take, and a
searchable log of every API call.

Nothing leaves your machine. Every port is bound to `127.0.0.1`.

## The idea in one line

Claude Code already speaks OpenTelemetry — you just have to give it somewhere to talk to.

Set `CLAUDE_CODE_ENABLE_TELEMETRY=1` and point `OTEL_EXPORTER_OTLP_ENDPOINT` at
`http://localhost:4317`, and the CLI pushes metrics and events to whatever is listening on that
port. This project is the thing that listens.

## What you get

| URL | What it is |
| --- | --- |
| <http://localhost:3000> | **Grafana** — dashboards. Start here. |
| <http://localhost:9090> | **Prometheus** — raw metric queries |
| <http://localhost:3100> | **Loki** — raw event/log queries |
| <http://localhost:8000> | **These docs** |
| `localhost:4317` | OTLP gRPC — the endpoint Claude Code writes to |
| `localhost:4318` | OTLP HTTP — same, over HTTP |

## Two kinds of data

This is the single most important thing to understand, and everything else follows from it.

**Metrics** are numbers aggregated over time — *"$4.18 spent, 2.1M tokens, 37 sessions."*
They are cheap, they compress well, and they answer *how much*. They live in **Prometheus**.

**Events** are individual records with rich attributes — *"this specific API call at 20:51:33 used
Haiku, cost $0.018, took 1425ms, request ID `req_01ExampleRequestId...`"*. They answer *what happened*.
They live in **Loki**.

You want both. A cost spike in Prometheus tells you *that* something happened; the events in Loki
tell you *which requests* caused it.

## Is it working?

The fastest check, after a session has run:

```bash
curl -s http://localhost:8889/metrics | grep claude_code
```

If you see `claude_code_token_usage_tokens_total{...}` lines, the whole chain is working.

---

Next: **[How it works](how-it-works.md)** for the architecture, or
**[Quickstart](quickstart.md)** if you just want it running.
