<!-- META:idastone-construction -->
# Features — exhaustive built / partial / planned list

Authoritative status of every shipped, in-flight, and planned piece.
**Update this file in the same commit that changes status.**

Last big sweep: 2026-04-27.

## Built and dogfooded

### Repo + distribution
- Apache-2.0 LICENSE (full 202-line text)
- NOTICE attributing every vendored OSS pattern source
- CHANGELOG.md, SECURITY.md, CONTRIBUTING.md
- `.github/ISSUE_TEMPLATE/` (bug, port_proposal), `pull_request_template.md`
- Smoke test: 69+ assertions covering every shipped CLI + hook
- CI: `.github/workflows/smoke.yml` runs smoke + installer-merge on Ubuntu (free tier)
- Self-hosted runner workflow: `.github/workflows/claude-review.yml` (Mac mini + Claude Max → PR review)
- `tests/smoke-test.sh` with `--scope since` audit support

### Schema (workflow.db)
- `learnings` + `learnings_fts` (FTS5 + porter unicode61)
- `dead_ends` + `dead_ends_fts` (mirror pipeline)
- `experiments` + `experiments_fts` (AIDE journal tree, B1)
- `code_pool` (table; CLI not yet wired — C3)
- `hypothesis_calibration` + `calibration_scorecard` view (A2)
- `experiment_queue` with atomic claim semantics
- `budget_usage` with session/project scoping
- `gpu_pods` with `accrued_dollars` + `last_reconciled_at`
- `sessions`, `notifications`
- Schema versioning via `PRAGMA user_version` + `memory/migrations/NNN_*.sql` walker
- Migrations 002 (gpu_pods accrued cols) shipped

### Hooks (project-harness)
- `learn-capture.sh` (Stop) — parses `[LEARN]`, parameterized SQLite insert, ticks wallclock + tokens
- `deadend-capture.sh` (Stop) — parses `[DEAD-END]`, parameterized
- `correction-detect.sh` (UserPromptSubmit) — regex nudge + counter
- `load-relevant-rules.sh` (UserPromptSubmit) — BM25 with score gate
- `load-relevant-deadends.sh` (UserPromptSubmit) — brainstorm-gated
- `stuck-detector.sh` (UserPromptSubmit) — 4 loop types, periods 2/3/4
- `stage-inject.sh` (UserPromptSubmit) — `## Stage:` section emission
- `budget-reconcile.sh` (UserPromptSubmit) — 120s TTL, calls gpu.py reconcile
- `session-report.sh` (SessionStart) — emits JSON envelope additionalContext
- `doc-guard.sh` (PreToolUse Write|Edit) — short-circuits before log rotate on non-md
- `pre-commit-gate.sh` (PreToolUse Bash) — clean-hash sentinel, `pwd -P` scope, runs in PROBE_CWD
- `pre-train-gate.sh` (PreToolUse Bash) — broadened regex (python3.11), # --smoke comment stripping, scope inversion fix
- `budget-gate.sh` (PreToolUse Bash) — exits 2 on ceiling cross

### Hooks (user-harness)
- `memory-session-start.sh` — surfaces cross-repo memories into rules-compiled.md
- `memory-pre-compact.sh` — backstop [LEARN] scan before context compaction
- `check-orphan-dashboards.sh` — throttled nudge for orphan /deploy-team Node dashboards

### Scripts (project-harness)
- `init_db.sh` — corruption-safe (sqlite_master probe vs zero-byte heuristic), migration walker
- `seed_hard_rules.py` — 14 generic + project-specific (via PROJECT env)
- `compute_clean_hash.sh` — portable sha256 (sha256sum / shasum / python3 fallback)
- `rotate_hook_log.sh` — keeps hook.log bounded
- `notify.sh` — ntfy push, parameterized DB writes, AppleScript-injection-safe (osascript heredoc with system attributes)
- `ntfy_poll_responses.sh` — cursor-based, filters robot_face tags
- `journal.py` — AIDE journal CLI (add/start/close/kill/tree/best/leaves/status/render); imports VALID_STAGES from stage.py
- `queue.py` — experiment queue (add/next/done/drop/release/reap/list/status/refill-needed); claim ownership check; `--force` override
- `calibration.py` — predicted vs actual delta scorecard
- `budget.py` — 4-dimension counter; `tick-wallclock`, `tick-tokens`, scoped `reset`; rejects empty CLAUDE_SESSION_ID
- `zcm.sh` — zero-cost monitor with anomaly detection, narrowed Killed regex
- `autopilot_loop.sh` — outer dispatcher with anti-burn exponential cooldown, flock-based lock, exports config vars
- `dry_run_gate.sh` — register/check content-hashed sentinels
- `apply_patch.py` — SEARCH/REPLACE format, .NNN.bak backups, path-traversal refusal (resolved + cwd-relative)
- `convergence.py` — token detector for reflection loops
- `stage.py` — canonical VALID_STAGES; get/set/list
- `runpod.py` — auth/list-gpus/price/create/list-pods/get-pod/stop/terminate/resume/cost/reconcile; min-bid default; UA fix for Cloudflare
- `repair_fts.sh` — FTS5 rebuild for any of the three indexes
- `session_report.py` — robust against half-initialized DBs
- `autopilot.conf` parser — allow-listed key=value, refuses $(…) and backticks (replaced shell-source)

### Skills (project-harness)
- `/clean` — pre-commit anti-slop audit (--scope staged/dirty/since)
- `/deploy-team` — Python orchestrator + 3 templates (gauntlet, pre-launch-audit, post-run-analysis)
- `/post-run-review` — structured Assess→Codify (SKILL.md only; runtime is the agent)
- `/queue-refill` — brainstorm new queue items
- `/scheduled-notes` — cross-wakeup persistent notes
- `/autopilot` — continuous-ops mode preflight + invocation
- `/propose-harness-change` — Generator/Verifier/Updater for safe self-improvement

### Skills (user-harness)
- `/deploy-team` (global definition)

### Templates + assets
- `claude-md/CLAUDE.md.template` — generic
- `claude-md/ml-research.md` — ML preset with predicted_delta requirement + [DEAD-END] mention
- `examples/seed_example_ml_research.py` — ML-specific rules a user can adapt
- `examples/launch_experiment.example.sh` — launcher template (autopilot.conf documented)
- `install-assets/gitignore.idastone` — block merged into user .gitignore (BEGIN/END markers)
- `project-harness/budget.toml.example` — commented-out template
- `project-harness/autopilot.conf.example` — documents allow-listed keys

### Documentation (user-facing)
- `README.md`
- `docs/ARCHITECTURE.md` — event flow + storage model
- `docs/quickstart.md`
- `docs/install.md`
- `docs/ntfy-setup.md`
- `docs/budgets.md` — 4-dimension auto-tracking + persona guidance
- `docs/environment.md` — `.env` pattern + rotation
- `docs/PORTS.md` — 11-repo source-level review + 60-day arXiv scan + license matrix
- `docs/self-hosted-runner.md` — Mac mini setup
- `docs/providers-impl-spec.md` — implementation spec for next agent (Vast/Prime/Shadeform)
- `docs/_internal/stars.md` — gitignored positioning doc
- `docs/_internal/gpu-arbitrage-agent-prompt.md` — gitignored prompt for impl agent

## In-flight (parallel agent work)

### gpu-arbitrage agent (running independently per user)
- `providers/base.py` — Provider Protocol + dataclasses
- `providers/runpod.py` — refactor of runpod.py into class
- `providers/vast.py` — per spec §A
- `providers/primeintellect.py` — per spec §B
- `providers/shadeform.py` — per spec §C
- `gpu.py` — top-level router with cooldown filter, --allow-on-demand gate
- Migration 003: `preemption_events` table
- Smoke-test additions for router with mocked providers
- `docs/providers-setup.md` — account-setup checklists
- `.env.example` updated for VAST/PRIME/SHADEFORM keys (already landed in repo)
- `budget-reconcile.sh` updated to call `gpu.py reconcile` (already landed)

### Repo-organization research (background; just returned)
- See `LESSONS.md` for the canonical doc set Levanter / nanochat / DINOv2 / lm-eval-harness / AI-Scientist converge on
- Recommends adopting `AGENTS.md` (industry standard, not invented) — see ROADMAP

## Outstanding (next sprint or later)

### Documentation contract — the AGENTS.md sprint (next)
- `AGENTS.md` adoption (replaces invented MO.md idea)
- `agents-md-templates/{ml-research,web,security}.md`
- `.playbooks/<task>.md` directory + skill that loads the relevant playbook
- `docs/Getting-Started-<HW>.md` per-hardware (Levanter pattern)
- `docs/footguns.md` — explicit pitfalls (lm-eval-harness pattern)
- Per-experiment `manifest.json` (git_sha, hardware_id, env_lockfile_hash, config, seed)
- `pre-train-gate.sh` extended to verify hardware-match against parent's manifest.json
- `queue.py preflight <id>` — script/data/checkpoint existence check before claim

### Tier-A roadmap items (smaller wins)
- `[LEARN] paper-controls: hardware parity rule` — to write
- A4 three-mode search policy (AIDE) — depends on B1 journal (shipped)
- A5 stage-gated CLAUDE.md (shipped via stage-inject) — confirmed
- B5 timeout → forced-final-answer failover (deferred, low value w/o direct SDK hook)
- B7 `/replan` skill — pairs with stuck-detector
- C3 best-so-far code pool CLI (schema shipped)
- C4 failure-class taxonomy upgrade — adopt arXiv 2603.06847's 13-category as second enum
- Hard schema migration on `manifest.json` requirement: `journal.py close` rejects done without manifest

### Tier-B (week-scale)
- VLM plot reviewer (B2)
- Bias-probe panel reviewer (B6 — new /deploy-team template)
- Persona-parallel waterfall (B8) — depends on budget controller (✓)
- Anthropic 3-agent harness (planner/generator/evaluator + context-reset) — from 60-day research scan
- File-as-Bus workspace-map upgrade — STATE.md → structured map
- Two-tier memory (HCC) — frozen brief + rolling log + cross-task wisdom
- Hindsight four-network memory schema

### Tier-C (strategic)
- C1 staged macro-workflow (Sakana v2 reimpl)
- C5 Semantic Scholar novelty loop
- AgentRxiv-style embedding retrieval
- workflow.db ↔ memory.db promotion bridge
- GVU operator separation runtime (skeleton in /propose-harness-change)
- Network-volume support in runpod.py create
- Cumulative-historical accurate dollars (currently overcounts on terminate)
- ZCM integration with budget reconciliation
- Stuck detector → automatic /replan trigger

### Credibility artifacts (launch prerequisites)
- MLE-bench Lite submission (target the AIDE-current-champion comparison)
- Single famous-paper reproduction demo (asciinema or similar)
- "Catches a real bug" blog post (top-10 from this user's [LEARN] DB)
- Bug-catch rate benchmark vs AIDE/Sakana (intentionally-broken script corpus)
- Failure-taxonomy dataset publication (after C4 enum upgrade lands)

### Explicitly de-scoped (don't revisit)
- Paper / LaTeX writeup pipelines (out of scope; idastone is research, not paper-gen)
- Full RAG over a paper corpus (PaperQA2-style — overkill until a fixed corpus exists)
- smolagents AST sandbox (not a real sandbox per author admission)
- AutoGen / CrewAI orchestration DSL (Claude Agent SDK covers it)
- HITL prompts (we are autonomous-first; ntfy + sentinels cover human escapes)
- Ouroboros self-rewriting methodology loop (metric-gaming risk; GVU is the safer path)
- AI-Scientist NeurIPS 9-dim rubric (designed for papers, not code)
- AI-Researcher idea_agent self-novelty scoring (worse than waterfall)
- Paper2Code 4-stage planning (pre-experiment checklist covers it)
- GPU-aggregator-as-a-business (margins thin; competitors VC-funded; not our differentiator)
