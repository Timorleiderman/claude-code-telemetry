# Privacy

## What this stack collects by default

Metadata, not content. Token counts, costs, durations, model names, timestamps, and identifiers.

It also collects, unavoidably, some things about **you**: `user_email`, `user_account_id`,
`user_account_uuid`, `organization_id`, `host_name`. These are attached by Claude Code and appear
on every metric and event.

It does **not** collect your prompts, Claude's responses, file contents, or tool arguments —
unless you switch that on.

## Where it goes

Nowhere. Every published port is bound to `127.0.0.1`:

```yaml
ports:
  - "127.0.0.1:4317:4317"
```

That prefix is doing real work. Without it, Docker binds `0.0.0.0` and anyone on your network — a
coffee shop Wi-Fi, a shared office LAN — could reach your Grafana and read your usage data. Keep
the prefix.

## Content logging

These five flags change the nature of what's stored:

| Variable | What lands in Loki |
| --- | --- |
| `OTEL_LOG_USER_PROMPTS` | Everything you type into Claude Code |
| `OTEL_LOG_ASSISTANT_RESPONSES` | Everything Claude writes back |
| `OTEL_LOG_TOOL_DETAILS` | Tool parameters — file paths, bash commands, search strings |
| `OTEL_LOG_TOOL_CONTENT` | Tool inputs and outputs — **file contents** |
| `OTEL_LOG_RAW_API_BODIES` | The complete API request and response JSON |

!!! danger "Think before enabling these"
    They are commented out in `claude-telemetry.env` on purpose.

    If you work on a codebase with secrets in it, `OTEL_LOG_TOOL_CONTENT` will write those secrets
    into Loki in plaintext, sitting in a Docker volume, retained for 90 days. The same goes for
    anything you paste into a prompt — API keys, customer data, credentials from a `.env` file.

    Loki has no access control in this configuration. Grafana has no login.

They're genuinely useful for debugging *why* a session went sideways.

## Toggling mid-session

Claude Code re-reads `~/.claude/settings.json` while running and applies the `env` block live. You
do **not** need to restart to turn content logging on or off.

Add to the `env` block to enable:

```json
"OTEL_LOG_USER_PROMPTS": "1",
"OTEL_LOG_ASSISTANT_RESPONSES": "1",
"OTEL_LOG_TOOL_DETAILS": "1"
```

Delete those lines to disable. Both directions take effect on your next message.

Confirmed on a single running session — the boundary is visible in the data, with no restart in
between:

```
21:35:21  len=59  prompt=<REDACTED>
21:39:05  len=22  prompt=fix the failing auth test
```

!!! warning "It stays on until you remove it"
    There's no session-scoped expiry. Once those keys are in `settings.json`, **every** Claude Code
    session on this machine logs content until you delete them. Editing the file is the off switch.

## Or use the wrapper, and never touch global config

`./claude-verbose` is still the safer habit for one-off investigations: it sets the flags on a
single process, so there's nothing to remember to turn off afterwards and no window where an
unrelated session is logging your prompts.

## `./claude-verbose` — content logging for one session

The repo ships a wrapper that enables content logging for the session it launches and nothing else.
`~/.claude/settings.json` is never touched, so every other Claude Code window keeps recording
metadata only.

```bash
./claude-verbose           # prompts + responses
./claude-verbose --tools   # + tool parameters (bash commands, file paths)
./claude-verbose --full    # + tool output and raw API bodies
```

Arguments pass through to `claude`, so `./claude-verbose --tools -p "..."` works.

It prints a warning banner naming the level before launching, and tags every event with
`content_logging=<level>` so verbose sessions are easy to find later. It also applies the
`project` / `dir` tags itself — the `tag-sessions.sh` shell function can't reach a script, since
shell functions aren't inherited by child processes, so without this a verbose session would show
up untagged in `--sessions`.

### What each level actually captures

The default and `--tools` columns were confirmed by running them and reading what landed in Loki.
`--full` adds `OTEL_LOG_TOOL_CONTENT` and `OTEL_LOG_RAW_API_BODIES` on top; its column reflects
what those flags are documented to do, not a capture I ran.

| | default | `--tools` | `--full` |
| --- | --- | --- | --- |
| `user_prompt.prompt` | your text | your text | your text |
| `assistant_response.response` | Claude's text | Claude's text | Claude's text |
| `tool_decision.tool_parameters` | `<REDACTED>` | **full command** | full command |
| `tool_result.tool_input` | absent | **full input JSON** | full input JSON |
| tool *output* content | size only | size only | **full output** |
| raw API request/response JSON | no | no | **yes** |

A concrete `--tools` capture:

```json
{
  "event_name": "tool_result",
  "tool_name": "Bash",
  "tool_input": "{\"command\":\"npm test\",\"description\":\"Run the test suite\"}",
  "tool_result_size_bytes": 9,
  "content_logging": "tools"
}
```

Note `--tools` records the command you ran but only the *size* of what it returned. `--full` is what
captures output — and therefore file contents. That's the level to be careful with.

### Finding and removing verbose sessions

Because of the tag, they're easy to isolate:

```logql
{service_name="claude-code"} | content_logging != ""
```

To get rid of collected content entirely, `docker compose down -v` wipes all three volumes. (Loki
also exposes a delete API, which this config's compactor has enabled, but deletions there are
asynchronous — the wipe is the predictable option.)

## Grafana has no password

`GF_AUTH_ANONYMOUS_ENABLED=true` with `GF_AUTH_DISABLE_LOGIN_FORM=true` means anyone who reaches
port 3000 gets admin. That's a reasonable trade for a localhost-only tool and a bad one the moment
it's exposed. If you ever change the port binding, remove those two environment variables from
`docker-compose.yml` first.

## Reducing what's collected

Drop the identifying labels from metrics:

```bash
export OTEL_METRICS_INCLUDE_ACCOUNT_UUID=false   # no user.account_uuid / user.account_id
export OTEL_METRICS_INCLUDE_SESSION_ID=false     # no session.id
```

`user_email` and `user_id` aren't controlled by a flag. To strip them, do it in the collector —
add to `otel-collector-config.yaml`:

```yaml
processors:
  attributes/scrub:
    actions:
      - key: user.email
        action: delete
      - key: user.id
        action: delete
```

Then add `attributes/scrub` to the processors list in both pipelines. The collector is the right
place for this: it applies to everything, regardless of how a session was started.

## Deleting it all

```bash
docker compose down -v
```

Drops the containers and the three data volumes. Nothing survives.
