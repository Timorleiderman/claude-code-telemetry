# Inspecting your usage

## Start here: what did each message cost?

```bash
./usage-report -m
```

With no arguments it picks **the session you're currently in** — the most recently active one — and
lists every message with its price and a running total:

```
  session 5e551011  —  9 messages, $5.8476
  ────────────────────────────────────────────────────────────────────────────
  time      id             cost       cum  req     out  message
  ──────────────────────────────────────────────────────────────────────────────────
  21:20:01  9r0m9703    $1.2379   $1.2379    3   3,868  <redacted, 61 chars>
  21:22:42  9r0m9702    $0.4971   $1.7350    5   4,381  <redacted, 23 chars>
  21:31:37  9r0m9705    $1.1243   $3.5525   11   9,179  <redacted, 62 chars>
  21:39:05  9r0m9707    $0.4290   $4.3659    4   3,212  fix the failing auth test
  21:40:17  9r0m9706    $1.1141   $5.4800    9  10,230  write the migration guide for v2
  21:45:27  9r0m9709    $0.3676   $5.8476    3   3,252  make the CLI output easier to scan
  ──────────────────────────────────────────────────────────────────────────────────
  priciest: $1.2379 at 21:20:01
  drill into any row:  ./usage-report --prompt <id>   (e.g. 9r0m9703)
```

The `req` column is the number of API calls one message triggered — note the message that cost
$1.12 across **11 calls**. The footer hands you the exact command to dig into the worst one.

Message text appears only if [content logging](privacy.md) was on when you sent it; otherwise you
get the length, which is usually enough to recognise it alongside the timestamp.

Other sessions:

```bash
./usage-report -m --session 04fd     # prefix is enough
./usage-report --sessions            # list them first
```

Rows marked *(background / subagent work)* are API calls with no user message behind them —
subagents and background tasks, billed to the session but not to anything you typed.

## Then: what has this cost me overall?

```bash
./usage-report
```

```
  last 24h — 38 requests
  ──────────────────────────────────────────────────────────
  cost              $4.5259
  avg / request     $0.1191
  output tokens     33,102
  cache read        4,705,916
  cache created     146,847
  fresh input       3,114
  cache hit rate    99.9%
  latency           p50 12.0s   p95 29.9s

  by model
    claude-opus-5                  34 req      $4.4912  ████████████████████████  99.2%
    claude-haiku-4-5-20251001       4 req      $0.0347  ························   0.8%
```

`--since` takes `30m`, `24h`, `7d`, `4w`. Add `--watch` for a live-refreshing view while you work.

Every number is a sum of real per-request values from the `api_request` events, not a counter
approximation — so it reconciles exactly with what you'd compute by hand.

## Which session burned it?

```bash
./usage-report --sessions
```

```
  5e551011     36 req      $4.8078   36,739 out  ████████████████ 21:41:26
  5e551013      2 req      $0.0139      171 out  ················ 21:33:05
  5e551012      1 req      $0.0104       52 out  ················ 21:08:43
```

Usually one session dominates. That's normal — long working sessions carry large context.

## Which prompt was expensive?

This is the one that changes behaviour. **One thing you type is not one API call.**

```bash
./usage-report --prompts
```

```
  cost by prompt (one thing you typed)  (11 total, $4.8425)
  9r0m9703      3 req      $1.2379    3,868 out  ████············
  9r0m9705     11 req      $1.1243    9,179 out  ████············
  9r0m9702      5 req      $0.4971    4,381 out  ██··············
```

A single message fanned out into 11 API calls costing $1.12. Tool loops, subagents and retries all
bill separately under the same `prompt_id`.

## What actually happened inside one message?

```bash
./usage-report --prompt 9r0m9704
./usage-report --prompt last        # the message you just sent
```

Every API call inside that message, every tool it ran, and what each one cost:

```
  message 9r0m9704  —  $1.5044 across 11 API calls, 11 tool calls, 195s wall
  "add pagination to the search endpoint"
  ──────────────────────────────────────────────────────────────────────────────
   1. 21:50:32  API call     $0.1856    44.9s   out=3,814  cacheRead=179,837
      21:50:32  response, 122 chars
      21:50:40  ✓ Edit       0.0s → 172B        .../usage-report
  ──────────────────────────────────────────────────────────────────────────────
   2. 21:50:40  API call     $0.1420     7.9s   out=531    cacheRead=179,866
  ──────────────────────────────────────────────────────────────────────────────
   3. 21:50:44  API call     $0.1015     3.6s   out=147    cacheRead=183,741
      21:50:46  ✗ Bash       FAILED 0.6s        git log --oneline | head -20
  ──────────────────────────────────────────────────────────────────────────────
   4. 21:50:49  API call     $0.0994     2.7s   out=164    cacheRead=184,333
      21:50:51  ✓ Bash       0.2s → 1,406B      npm run lint
  ...
  ──────────────────────────────────────────────────────────────────────────────
            cost   out tok   cacheRead  cacheCreate     dur
   1.   $0.1856     3,814     179,837           29   44.9s
   2.   $0.1420       531     179,866        3,875    7.9s
   3.   $0.1015       147     183,741          592    3.6s
  ...
        $1.5044    13,324
```

Read it as a loop: **API call → response → tool → API call**. Each tool result forces another
round trip, and each round trip re-reads the whole conversation. That's why the per-call cost is
almost flat at ~$0.10–0.18 regardless of how much the call produced — you're paying for context,
not output. Note call 1 generated 3,814 output tokens for $0.1856 while call 4 generated 164 for
$0.0994. Barely half the price for 4% of the output.

**So cost tracks the number of tool calls, not the length of your question.** The failed `Bash`
at step 3 cost a full extra round trip to recover from.

Tool commands and file paths appear only when `OTEL_LOG_TOOL_DETAILS` was on — see
[Privacy](privacy.md). Without it you still get tool names, timings, success and result sizes.

## Raw request records

```bash
./usage-report --top 5
```

```
        cost  time      model              cacheCreate   cacheRead      dur
     $1.0131  21:20:13  claude-opus-5           98,258      22,223    11.5s
     $0.1951  21:41:22  claude-opus-5            2,249     157,100    39.8s
     $0.1557  21:36:25  claude-opus-5            2,647     148,494    32.5s
```

## Reading the numbers

The `cacheCreate` / `cacheRead` columns above explain almost every cost surprise you'll have.

**The first call of a session costs ~10× the rest.** In the table, `$1.0131` wrote 98,258 tokens
into the prompt cache. Every call after it *read* ~150k tokens back and wrote only ~2k of new
context — about $0.13 each. Same conversation, same model, 8× cheaper.

The practical consequence: **long sessions are cheap; starting fresh ones repeatedly is not.**
Each new session pays the cache-write cost again. If you're iterating on one problem, staying in
one session is materially cheaper than restarting between attempts.

| Reading | Means |
| --- | --- |
| cache hit rate > 95% | Caching working normally. Nothing to do |
| cache hit rate low, `fresh input` high | Context being rebuilt repeatedly — likely restarting sessions |
| one request ≫ others, high `cacheCreate` | A session's first call. Expected |
| high cost, low `output tokens` | Paying for context, not generation. Long conversation |
| p95 latency ≫ p50 | A few heavy calls; check `--top` |

A hit rate of 99.9% with 3,114 fresh input tokens against 4.7M cache reads, as above, is close to
ideal.

## In Grafana

<http://localhost:3000/d/claude-code-usage/> for the visual version. Set the time picker first —
the default is 24h and often looks empty when you've just started.

- **Top row** — totals for the selected range
- **Tokens by type** — the cache story as a bar gauge
- **Middle band** — cost, latency percentiles and request counts over time, from events
- **Bottom log panel** — every request, newest first. **Click a row to expand** it; the one-line
  preview shows nothing but the detail holds cost, tokens, model, latency and `prompt_id`

To trace one prompt, copy its `prompt_id` from an expanded row into **Explore → Loki**:

```logql
{service_name="claude-code"} | prompt_id="9r0m9703-..."
```

## Notes on the tool itself

**Times are your local wall clock.** Claude Code emits UTC; `usage-report` converts. If you compare
against raw Loki or Grafana output, those show UTC and will look offset.

**Large ranges are safe.** Loki caps any single query at 5000 entries and truncates *silently* —
which would make a `--since 30d` report quietly under-count. `usage-report` splits the range and
recurses until every window fits, so totals stay complete. If it ever can't (a single 2-second
window with 5000+ events, which one person cannot generate) it prints a warning to stderr rather
than reporting a wrong number quietly.

**Piping is clean.** Colour is suppressed when stdout isn't a terminal, so
`./usage-report -m > report.txt` and `| grep` behave. `NO_COLOR=1` forces it off too.

**Pointing elsewhere.** `CLAUDE_TELEMETRY_LOKI=http://host:3100 ./usage-report` if you moved Loki.

## Ad-hoc questions

When the script doesn't cover it, [Query recipes](queries.md) has the copy-paste set. The two
worth memorising:

```promql
sum(max_over_time(claude_code_cost_usage_USD_total[$__range]))
```

```logql
sum by (model) (sum_over_time({event_name="api_request"} | unwrap cost_usd [$__interval]))
```

Use `max_over_time`, never `increase()` — see
[why](queries.md#read-this-first-why-increase-returns-0).
