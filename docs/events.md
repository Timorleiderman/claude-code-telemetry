# Events reference

Events are individual records, stored in Loki. Where metrics say *"$4.18 total"*, events say
*"this call, at this moment, cost $0.018."*

## Querying them

Loki's query language is LogQL. Start with a stream selector in `{}`:

```logql
{service_name="claude-code"}                          # everything
{service_name="claude-code", event_name="api_request"} # one event type
```

Only `service_name`, `service_version`, `host_name`, `os_type`, and `event_name` are indexed
labels — those are the only things valid inside `{}`. Everything else is structured metadata,
filtered *after* the selector with `|`:

```logql
{event_name="api_request"} | model="claude-opus-5"
```

This is deliberate; see [cardinality](how-it-works.md#cardinality-and-why-loki-is-configured-the-way-it-is).

## The full event list

| `event_name` | Fires when |
| --- | --- |
| `user_prompt` | You submit a prompt |
| `assistant_response` | The model returns text |
| `api_request` | An API request is made — **the richest one** |
| `api_error` | A request fails |
| `api_refusal` | The API returns `stop_reason: "refusal"` |
| `tool_result` | A tool finishes |
| `tool_decision` | A tool permission is accepted or rejected |
| `permission_mode_changed` | You change permission mode |
| `auth` | Login or logout completes |
| `mcp_server_connection` | An MCP server connects or disconnects |
| `hook_registered` / `hook_execution_start` / `hook_execution_complete` | Hook lifecycle |
| `plugin_installed` / `plugin_loaded` | Plugin lifecycle |
| `internal_error` | An unexpected internal error is caught |
| `api_request_body` / `api_response_body` | Only with `OTEL_LOG_RAW_API_BODIES` |

## `api_request` in full

Captured verbatim from this stack — this is what one event actually carries:

```json
{
  "event_name": "api_request",
  "model": "claude-haiku-4-5-20251001",
  "cost_usd": "0.0181107",
  "cost_usd_micros": "18111",
  "duration_ms": "1425",
  "input_tokens": "10",
  "output_tokens": "46",
  "cache_read_tokens": "18267",
  "cache_creation_tokens": "8022",
  "speed": "normal",
  "query_source": "sdk",
  "request_id": "req_01ExampleRequestId00000",
  "client_request_id": "c11e0700-0000-4000-8000-00000000000d",
  "prompt_id": "9r0m9701-0000-4000-8000-00000000000c",
  "session_id": "5e551011-0000-4000-8000-000000000001",
  "event_sequence": "9",
  "event_timestamp": "2026-08-11T20:51:33.822Z",
  "app_version": "2.1.228",
  "terminal_type": "Apple_Terminal",
  "user_email": "you@example.com"
}
```

Cost, latency, and the full token breakdown are on **every single request**. That's enough to answer
"which call was expensive and why" without any content logging at all.

## `user_prompt` — what it does *not* contain

Your prompt text is not stored by default. The attribute exists but is replaced with a literal
placeholder:

```json
{
  "event_name": "user_prompt",
  "prompt": "<REDACTED>",
  "prompt_length": 25,
  "prompt_id": "9r0m9700-0000-4000-8000-00000000000a",
  "message_uuid": "m5g0000e-0000-4000-8000-00000000000b",
  "session_id": "5e551012-0000-4000-8000-000000000002"
}
```

So you can see *that* you sent a 25-character prompt at a given moment, and follow everything it
triggered via `prompt_id` — but not what you wrote. Setting `OTEL_LOG_USER_PROMPTS=1` replaces
`<REDACTED>` with the real text. See [Privacy](privacy.md).

The same pattern applies to `assistant_response` and to tool arguments.

## The IDs, and how to correlate

| Field | Scope | Use it to |
| --- | --- | --- |
| `session_id` | One CLI session | Reconstruct everything one session did |
| `prompt_id` | One prompt | Group every API call, tool result and response from a single thing you typed |
| `request_id` | One API call | Match against Anthropic-side records in a support case |
| `client_request_id` | One API call | Follow retries client-side |
| `event_sequence` | Monotonic per session | Order events that share a timestamp |

`prompt_id` is the useful one day to day. One prompt often fans out into many API calls — tool use
loops, subagents, retries. Grouping by `prompt_id` tells you what a single request of yours really
cost:

```logql
{event_name="api_request"} | prompt_id="9r0m9701-0000-4000-8000-00000000000c"
```

## Body vs. attributes

The log *body* is just the event name (`claude_code.api_request`). Everything interesting is in the
attributes. In Grafana's Logs panel, click a line and expand it to see them all — don't judge the
data by the one-line preview.
