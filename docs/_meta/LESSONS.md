<!-- META:idastone-construction -->
# Lessons — explicit user feedback + audit findings

This file is the durable record of "things the user said" and
"things the audits found." Future agents should treat these as
load-bearing.

Earlier than 2026-04-23 entries are pre-history (the Pebble
internal harness era). The dated entries below begin with
idastone's OSS extraction.

---

## User preferences (durable, save also to memory)

### NO_OVERPROMPTING (2026-04-24)
> "I want to see what it does on its own. this is overprompting which
> bypasses the need for a harness."

**Rule:** Don't write hand-curated `NIGHT_ONE.md` / `HANDOFF.md` /
playbook files prescribing what a fresh agent should do. The
harness's job is auto-onboarding via SessionStart hook + canonical
docs. If an agent only succeeds with a hand-written playbook, the
harness is failing — fix the harness, not write more playbooks.

### MAX_SUBSCRIPTION_BUDGET (2026-04-24)
> "Tokens should be infinity, tool_calls infinity, wallclock infinity.
> Only GPU hours are not infinity."

**Rule:** For users on Claude Max running idastone locally, only
external compute spend (`dollars`) corresponds to real money.
Default `.claude/budget.toml` ships with `[project] dollars` only.
Other dimensions are tracked but not capped unless user opts in.

### SPOT_BID_MIN (2026-04-24)
> "Always start spot GPU bids at minimum; raise only after preemption."

**Rule, refined:** Always start spot bids at min. On preemption,
**hop to a different provider at THAT provider's min**, not bump
the bid. On-demand is last-resort only.

### NO_PARALLEL_MAIN_WORK (2026-04-24)
> "I think you have a tendency to lose track when you do stuff in
> parallel. Just try to keep it like a cascade. Do one thing after the
> other. Use sub-agents when you need fresh context."

**Rule:** Cascade-only for the main agent's primary work.
Subagents (Agent tool) for research / fresh-context audits / code
spread are fine and encouraged. Parallel main-thread work loses
track.

### COMMIT_SIGNING (pre-2026-04)
> "Don't add Co-Authored-By Claude trailers to git commits."

**Rule:** Author commits as the user; no Claude trailer.

### SUBAGENT_MODEL_POLICY (pre-2026-04)
**Rule:** Sonnet for workhorse subagents (research, fix-list
application). Opus for architect / attack / high-risk.

### RESEARCH_RECENCY (pre-2026-04)
**Rule:** Research agents on ML/AI must prioritize recent work
(last 6-12 months). Neuroscience and mature fields exempt.

### SMALL_INCREMENTAL_COMMITS (2026-04-24)
> "Commit incrementally if you can, the more commits the better."

**Rule:** One feature per commit, atomic, small, clear what/why
message. Match existing `git log --oneline -20` style.

---

## Audit findings — security

### apply_patch.py path traversal (CRITICAL, fixed 2026-04-23)
LLM-produced patches could write to absolute paths or escape via
`..`. Fix: resolve each path against cwd; reject if not contained.

### autopilot.conf shell-source = ACE (CRITICAL, fixed 2026-04-24)
Original `. "$CONF"` made the file an arbitrary-code vector.
Replaced with allow-listed key=value parser that refuses `$(…)`
and backticks. Added to `.gitignore`.

### LICENSE was truncated (CRITICAL, fixed 2026-04-24)
17 lines vs Apache-2.0's 202. Fetched the full text.

### YOUR-ORG placeholder broke first-contact install (CRITICAL, fixed 2026-04-24)
README, quickstart, install.md, CONTRIBUTING all said
`git clone https://github.com/YOUR-ORG/idastone.git`. Replaced with
`saml212`.

### Cascade leftover from rename (MAJOR, fixed 2026-04-24)
Node orchestrator package.json + lockfile + migrate-jsonl.py still
named "cascade-team-orchestrator" after the rename. Scrubbed.

### Schema versioning was missing (CRITICAL, fixed 2026-04-24)
`CREATE TABLE IF NOT EXISTS` is silent on column changes. Added
`PRAGMA user_version` + `memory/migrations/NNN_*.sql` walker.

### Pre-commit-gate macOS path mismatch (MAJOR, fixed 2026-04-23)
`/var/folders` vs `/private/var/folders` symlink mismatch caused
gate to falsely "different repo" → skip. Fix: `pwd -P` canonicalize.

### Pre-train-gate regex bypass (MAJOR, fixed 2026-04-24)
`python3?` missed `python3.11`; `# --smoke` shell comment bypassed
smoke-exception. Fix: broaden regex + strip `#`-comments before
checks.

### Budget bypass via empty CLAUDE_SESSION_ID (MAJOR, fixed 2026-04-24)
Empty string generated key `session::tokens` which silently
bypassed ceiling check. Fix: reject empty session id, fall through
to "cli".

### Init_db.sh wiped WAL of active writer (MAJOR, fixed 2026-04-24)
Heuristic "zero-byte file → corrupted, delete" was wrong: WAL-mode
DBs legitimately have 0-byte main file mid-transaction. Fix:
sqlite_master probe.

### SessionStart stderr never reached agent context (MAJOR, fixed 2026-04-26)
Hooks were firing but the report wasn't in the agent's context.
Stderr in SessionStart goes to the human's startup banner, not the
prompt. Fix: JSON envelope `{hookSpecificOutput: {hookEventName,
additionalContext}}` on stdout.

### Spot pod created at min bid + preempted in < 5 min (OBSERVED 2026-04-26)
Two preemptions on H100 SXM at $1.50 within an hour. Single-provider
harness has no automatic hop. Mitigation: provider arbitrage sprint
in flight. Interim: docs flag this behavior; user can manually
attempt different gpu_type or wait.

### Round 4 didn't save checkpoints (DOGFOOD 2026-04-27)
Control A blocked because `pure_sft_seed*.pt` were never saved by
the original Round 4 training script. CLAUDE.md says "save the
exact script alongside results" but no enforcement. Fix in roadmap:
journal.py close requires manifest.json that includes
checkpoint_path; preflight verifies referenced checkpoints exist
before queue-claim.

### Wrong-hardware control proposal (DOGFOOD 2026-04-27)
Agent proposed running paper-control Control A on A100 because
spot was cheaper, when the original SFT runs were H100. User had
to articulate experimental rigor. Fix in roadmap: per-experiment
`manifest.json` + pre-train-gate hardware-parity check.

### Memory poisoning surface on `[LEARN]` (THEORETICAL, KNOWN)
arXiv 2601.05504 (MINJA) + 2604.02623 (eTAMP) — durable memory
with external-write channel is an attack surface. Today, learn-
capture parses any assistant text. Future GVU operator separation
runtime is the documented mitigation. Tracked as roadmap.

---

## Architecture findings — composition / soundness

(From the multi-agent audit on 2026-04-23)

### Tool_calls budget unfairly biased (MAJOR, partially fixed)
`budget-gate.sh` runs LAST in the PreToolUse(Bash) chain. If
pre-commit-gate or pre-train-gate exits 2 first, tool_calls never
increments — so blocked commits don't charge budget while harmless
ls calls do. Documented; not yet repaired.

### Zombie queue claims (MAJOR, fixed)
`queue.py reap --older-than-hours N` flips claimed → pending for
zombies; autopilot_loop calls reap at startup.

### Autopilot.lock was touch, not flock (MAJOR, fixed)
Two autopilots could race. Fixed via `exec 9>"$RUN_LOCK"; flock -n 9`.

### Two checkouts collide on project name (MAJOR, fixed)
Default project_name = `pathlib.Path(...).parents[2].name` →
`~/proj` and `~/backup/proj` both report "proj". Installer now
stamps a UUID into `.claude/project_id` on first install.

### No FTS5 rebuild path (MAJOR, fixed)
Shadow-table corruption was unrecoverable. Added `repair_fts.sh`.

### `[LEARN]` regex captures inside code fences (MINOR, documented)
`[LEARN] <category>: ...` inside ``` fences is captured if it
matches the pattern. Documented in handoff doc + PHILOSOPHY:
use angle brackets `<placeholder>` for examples (which fail the
char class) and don't emit real-shaped examples in the same turn
as real learnings.

---

## DX findings (live-session observations)

### "What is your instruction" failure mode (2026-04-26)
Agent burned 3 turns figuring out where the operational runbook
lived. AUTOPILOT_HANDOFF.md, WORKFLOW_FOR_AGENTS.md, H100_SETUP.md
exist but are not surfaced by SessionStart. Roadmap fix: AGENTS.md
schema sprint.

### "I was about to improvise" admission (2026-04-26)
Agent literally said it was about to improvise bootstrap from
general ML knowledge. Documented runbooks weren't pulling their
weight because nothing forced reading them. Roadmap fix: AGENTS.md
+ playbooks + manifest gate.

### Reading order isn't enforced (2026-04-26)
The harness assumed conscientiousness, not contract. Roadmap fix:
gate hooks per doc category (hard gate for env+runbook, inline for
research+state, heavy nudge for rest).

---

## Things that worked well (don't undo these)

- Min-bid default + provider-hop philosophy: caught a real preemption
  scenario gracefully
- Smoke test discipline: caught the autopilot env-export bug, the
  GNU-mktemp-vs-BSD bug, the YAML parse error
- /clean skill + pre-commit-gate: blocked at least one would-be
  commit-with-debug-prints
- The 4-layer privacy convention (`.claude/_local/`, `_private/`,
  `docs/_internal/`, `*.private.md`)
- JSON-envelope SessionStart fix: agent immediately had full context
  on next session
- License-gate discipline (Sakana code never vendored, only patterns
  reimpl'd)
- /propose-harness-change Generator/Verifier/Updater pattern: keeps
  the agent from auto-pushing while making upstreaming legitimate

---

## What we DIDN'T learn yet (open observation gaps)

- Real overnight autonomous run hasn't completed end-to-end. Every
  attempt has been derailed by env / data / hardware / preemption
  issues. Once one DOES complete, expect new lessons.
- The Provider-hop value claim (provider arbitrage saves cost +
  reliability) is design-only; not yet measured against a
  single-provider baseline.
- The `[LEARN]` DB hasn't been pressure-tested against memory
  poisoning. GVU runtime not built.
- The smoke test, while large, has zero coverage of the
  multi-agent /deploy-team Node orchestrator beyond syntax.
