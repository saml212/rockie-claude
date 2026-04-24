# Architecture

idastone is a set of Claude Code hooks, skills, and SQLite-backed
memory. There's no runtime server in the critical path — everything
runs from shell hooks fired by Claude Code events.

## Two installation tiers

```
<your-project>/.claude/       ← project-harness/   (tracked: hooks, skills, schema)
                              ← project-harness/   (gitignored: workflow.db, sentinels)
~/.claude/                    ← user-harness/      (cross-project: memory lib, team orchestrator)
```

`settings.json` (tracked) holds hooks. `settings.local.json`
(gitignored) holds per-user permissions and plugin enables. Hooks
**must** live in `settings.json` — hooks placed in `settings.local.json`
do not fire (verified; one of the early bugs we hit).

## Event flow

```
UserPromptSubmit ──► correction-detect.sh   (regex nudge + sessions.corrections_count++)
                 ├─► load-relevant-rules.sh (FTS5 BM25 → inject top-5 rules via stderr)
                 └─► check-orphan-dashboards.sh (user-global; /deploy-team reaper)

PreToolUse(Write|Edit) ──► doc-guard.sh     (soft warn on new .md files)
PreToolUse(Bash)       ──► pre-commit-gate.sh (blocks `git commit` unless /clean sentinel valid)

Stop ──► learn-capture.sh                   (parse [LEARN] blocks; INSERT OR IGNORE into workflow.db)

SessionStart ──► memory-session-start.sh    (user-global; surface memories → rules-compiled.md)
PreCompact   ──► memory-pre-compact.sh      (user-global; backstop [LEARN] scan)
```

## Storage model

Three SQLite / markdown stores, each with a distinct purpose:

### `.claude/memory/workflow.db` (per-project FTS5)

Tables:

- `learnings(id, created_at, project, category, rule, mistake, correction, source, times_applied)`
  - UNIQUE on `(COALESCE(project,''), category, rule)` → atomic dedupe via `INSERT OR IGNORE`
- `learnings_fts` — FTS5 virtual table over `(category, rule, mistake, correction)` with `porter unicode61` tokenization
- `sessions(id, project, started_at, ended_at, edit_count, corrections_count, prompts_count)`
- `notifications(id, sent_at, tier, title, body, topic, ntfy_id, correlation, acked_at, response)`

FTS5 triggers `ai/ad/au` keep the FTS index in sync. `PRAGMA
trusted_schema=1` is required on every write connection.

### `~/.claude/memory/memory.db` (cross-repo, promotion-based)

Different schema. `project` column: repo name or `NULL` for global.
Rules that appear in ≥3 projects auto-promote to global tier. Managed
by the `user-harness/scripts/memory/` lib.

**The two stores are intentionally not synchronized.** `workflow.db`
is your project's cognitive surface — fast FTS5 search, hot path on
every prompt, tuned per-project. `memory.db` is durable cross-repo
wisdom — patterns that survived multiple projects and deserve the
global-tier promotion. A bridge (`scripts/memory/promote.py`, not yet
shipped — roadmap item) would copy sufficiently-hit rules from
`workflow.db` into `memory.db`. Until that lands, the two stores
coexist; most users only need `workflow.db`.

### `~/.claude/projects/<project>/memory/*.md` (auto-memory markdown)

Hand-curated memory files indexed from `MEMORY.md`. These are the
Anthropic-side auto-memory system (not idastone-specific) — idastone
composes with it but doesn't manage it.

## The clean-hash sentinel

`/clean` writes `.claude/.state/clean-ok-<hash>` where `<hash>` =
`sha256(mode blobhash path ...)` over `git ls-files -s --staged`. The
pre-commit-gate recomputes the same hash and requires the sentinel
to exist. If you `git add` anything new, the hash changes and the old
sentinel becomes invalid — you have to rerun `/clean`.

Bypass: `CLEAN_BYPASS=1 git commit -m "..."` (use sparingly).

The gate is scoped — it only fires when the `git commit` targets the
repo that owns the hook. Commits in other repos aren't blocked by a
sentinel they don't know about.

## `/deploy-team` — two implementations

Both ship. Use either.

### Local Python (`project-harness/skills/deploy-team/`)

Orchestrator + templates. Markdown-only output (no UI). Defaults to
sequential because parallel breaks thread.md coordination when prompts
are one-shot. Templates: `gauntlet` (brainstorm → research → attack →
validate), `pre-launch-audit`, `post-run-analysis`, `blog-coherence`.

### Global Node (`user-harness/teams/`)

ES-modules Express server + live dashboard. Per-agent git worktrees.
JSONL intervention log supports `thread_post`, `stop_team`,
`stop_agent`, `pause_agent`, `resume_agent`. Run state at `.team-runs/`
(NOT `.claude/`, because Claude Code sandboxes writes under `.claude/`).

Pick based on the job: simple gauntlet → Python. Long-running team with
need to intervene → Node.

## ntfy push notifications (optional)

`scripts/notify.sh` publishes to an ntfy.sh topic with three tiers:

- **tier 1** — priority `max`, wakes phone through DND if whitelisted
- **tier 2** — priority `high`, normal push
- **tier 3** — priority `low`, silent / tray only

Every push is recorded in `workflow.db.notifications`. Responses come
back via `ntfy_poll_responses.sh` (cursor-tracked; filters
autopilot's own messages via `robot_face` tag). Requires
`NTFY_TOPIC` env var; skips silently otherwise.

See [ntfy-setup.md](ntfy-setup.md).

## Known non-obvious design choices

- **FTS5 MATCH on bare `-` is parsed as NOT-operator.** We strip
  hyphens from prompt tokens before MATCH.
- **`bm25()` is an FTS5 aux function — not usable inside aggregates.**
  We use `ORDER BY bm25(...) LIMIT 1` instead of `min(bm25(...))`.
- **Heredoc hijacks stdin even when a pipe is present.** Scripts use
  `python3 -c '…'` with inline-quoted source when piping needed.
- **`PRAGMA trusted_schema=1` is per-connection.** Every sqlite3 CLI
  invocation that writes to `learnings` prepends it.
- **sqlite3 must be `/usr/bin/sqlite3`.** PATH default on some boxes
  lacks FTS5.

## Roadmap

See [PORTS.md](PORTS.md) for the detailed port queue. Tier A is
same-day / same-week; Tier B is weeks; Tier C is multi-week.
