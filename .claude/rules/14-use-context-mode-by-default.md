# Rule: use context-mode by default for anything that might fill the context window

Default to **context-mode** (`ctx_execute`, `ctx_execute_file`,
`ctx_fetch_and_index` + `ctx_search`, `ctx_index`) for any action whose output
could consume context window — **not only actions with known-large output, but
anything whose size is unpredictable or non-trivial.** The raw bytes stay in the
sandbox; only what your code prints (a summary) enters the conversation.

The test is **"could this fill context?"**, not "is this big?" If the answer is
yes or *unsure*, use context-mode.

## What this covers (non-exhaustive)

- Any shell command whose output size you cannot bound in advance — `docker`
  build/inspect/logs/ps, `grep`/`find`/`rg`, `git log`/`git diff`/`git show`,
  package/dependency listings, `ls -R`, env dumps, test/lint/coverage runs.
- Reading a file in order to analyze, summarize, count, or extract from it —
  use `ctx_execute_file` so the file contents never enter context.
- Web/API content — use `ctx_fetch_and_index` + `ctx_search`, never paste a raw
  page/response into context.
- Any MCP tool output that may exceed a few lines.
- Iterating: when you'd otherwise read raw output and then reason over it, do the
  reasoning in code inside the sandbox and print only the conclusion.

## The few exceptions (raw Bash / `Read` is correct)

- A single command whose **entire** output is certainly tiny **and** you need it
  verbatim (e.g. `git rev-parse HEAD`, a one-line version check, `whoami`).
- File **mutations** — `Edit` / `Write` (context-mode does not mutate files).
- `Read` immediately before an `Edit` — `Edit` needs the exact bytes in context
  to match against. (To analyze rather than edit, prefer `ctx_execute_file`.)

When in doubt, prefer context-mode — the cost of an unnecessary sandbox round
trip is far smaller than the cost of an unbounded dump filling the window.

## Why

Context window is the scarcest resource in a long agent session, and output
size is often unknowable before you run the command. Treating context-mode as
the default (rather than a special case for "big" commands) removes the need to
guess — small results pass through cheaply, and a surprise 700 KB result never
blows the window. The reviews in `docs/audit/nitpicker-findings.md` (Pass
104–105) and the runtime validation were done this way: dozens of
docker/curl/grep/build actions produced only short summaries in context.

## Enforcement

The `context-mode` plugin is enabled in `.claude/settings.json`
(`enabledPlugins`) and installs a `PreToolUse` hook that auto-routes qualifying
Bash/MCP calls and redirects `curl`/`wget` to `ctx_fetch_and_index`, so the
default is enforced at the harness level, not just documented here.

## Verification

```bash
grep -q 'context-mode@context-mode' .claude/settings.json && echo "plugin enabled"
```

Run `/context-mode:ctx-doctor` for a health check and `/context-mode:ctx-stats`
to see how much context the session saved.
