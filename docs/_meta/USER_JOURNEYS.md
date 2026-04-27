<!-- META:idastone-construction -->
# User Journeys — what experience the harness delivers

There are two users of idastone: the **researcher** (human) and the
**agent** (Claude Code session running in the researcher's project).
Both must succeed. The harness fails when either's path is unclear.

## Journey A — The Researcher

### Day zero (one-time install)

```bash
git clone https://github.com/saml212/idastone.git ~/idastone
cd ~/idastone
./install.sh ~/path/to/your/research-project
```

The installer:
1. Drops `project-harness/` into `<project>/.claude/`
2. Drops `user-harness/` into `~/.claude/` (cross-project memory + Node teams)
3. Merges `settings.json` hook registrations (deduped, idempotent)
4. Merges `.gitignore` rules into the project (secrets, ML artifacts, agent scratch)
5. Stamps a UUID `project_id` so two checkouts don't collide
6. Initializes `workflow.db` with schema + 14 generic harness rules
7. Suggests dropping a `CLAUDE.md` from `claude-md/` templates

The researcher then:
- Drops `claude-md/ml-research.md` (or generic) at project root as `CLAUDE.md`
- Edits the `Project` section with their specifics
- Creates `.env` with `RUNPOD_API_KEY` (if using GPU) and `NTFY_TOPIC` (optional)
- Optional: registers the Mac mini as a self-hosted GitHub Actions runner
  for `claude-review.yml` PR reviews using their Claude Max subscription

### Day-to-day

1. Opens Claude Code in their research project. Hooks fire automatically.
2. Says anything (`hi`, `go`). The agent's first response is driven by
   the `SessionStart` hook's report (env, RunPod auth, queue, journal,
   stage), not by the prompt content.
3. Agent proposes one specific first action; researcher says `go` or
   redirects.
4. Standard loop: queue.next → provision GPU → run → review → close
   journal node → emit `[LEARN]` / `[DEAD-END]`.
5. For high-stakes reviews: researcher invokes `/deploy-team gauntlet`
   for multi-perspective scrutiny.
6. ntfy push on preemption / anomaly / cooldown — phone-aware.
7. To upstream a harness improvement found during work: agent emits
   `[LEARN harness-upstream]`; researcher later runs
   `/propose-harness-change`, reviews the verifier's output, opens a
   PR to saml212/idastone.

### Cost / safety

- `runpod.py cost` — instant snapshot: per-pod state, hourly rate,
  daily projection, cumulative budget.
- `budget.py status` — counters auto-tracked: tokens (transcript-
  bytes proxy), wallclock_s (Stop hook delta from SessionStart),
  tool_calls (each Bash call), dollars (RunPod reconciliation).
- `.claude/budget.toml` — opt-in ceilings per dimension.
  Max-subscription users typically only set `[project] dollars`.
- `gpu.py reconcile` — UserPromptSubmit hook with 120s TTL pulls
  truth from each provider, rewrites the dollars counter against
  reality.

## Journey B — The Agent

### Session start

`SessionStart` hook fires `session-report.sh`. Output goes via JSON
envelope (`hookSpecificOutput.additionalContext`) into the agent's
system prompt for the session — NOT stderr. (Stderr in SessionStart
hooks goes to the human's startup banner, not the agent.) The
report shows:

- Environment status: `.env` presence, which keys are set
- RunPod (or whichever providers are configured): authed user,
  running pods (with SSH endpoint), EXITED pods (resumable)
- Experiment queue: counts + top-priority pending item
- Best-so-far results + last 3 experiments
- Current stage (stage.py get)
- Tail of `STATE.md` and `SCHEDULED_NOTES.md` if present
- Explicit "what to do next" with a 5-step decision tree

### Per-turn hooks

`UserPromptSubmit` runs (in order):
1. `correction-detect.sh` — regex nudge if user corrects + increments sessions.corrections_count
2. `load-relevant-rules.sh` — FTS5 BM25 search over learnings, injects top-5 (gate at score < -4)
3. `load-relevant-deadends.sh` — same shape, but only on brainstorm-shaped prompts
4. `stuck-detector.sh` — 4 loop types over recent transcript
5. `stage-inject.sh` — emits matching `## Stage:` section from CLAUDE.md
6. `budget-reconcile.sh` — TTL'd cross-provider reconciliation

`PreToolUse(Write|Edit)` runs `doc-guard.sh` — soft warning on new `.md` files.

`PreToolUse(Bash)` runs (in order):
1. `pre-commit-gate.sh` — blocks `git commit` unless `/clean` sentinel exists for the staged hash
2. `pre-train-gate.sh` — blocks training-launcher commands without dry-run sentinel
3. `budget-gate.sh` — blocks any tool call when dollars/tokens/wallclock_s/tool_calls ceiling crossed

`Stop` runs:
1. `learn-capture.sh` — parses `[LEARN]` blocks, INSERT OR IGNORE into learnings (parameterized)
2. `deadend-capture.sh` — parses `[DEAD-END]` blocks into dead_ends (parameterized)
3. (inline in learn-capture) ticks wallclock_s + tokens budget counters

### Standard task arc

1. **Pick** — `queue.py next --json` atomically claims top-priority item.
2. **Plan** — open journal node via `journal.py add --stage <s>
   --hypothesis "..."`. Pre-experiment checklist enforced via CLAUDE.md.
3. **Provision** — `runpod.py create --gpu-type <id> --yes` (defaults
   to current min bid; never bump). Or `gpu.py create` once router
   is wired.
4. **Sync code+data to pod** — currently per
   `experiment-runs/_auto_sync/WORKFLOW_FOR_AGENTS.md`. Manifest
   discipline forthcoming via AGENTS.md schema.
5. **Run + monitor** — ZCM polls process via `kill -0` + `nvidia-smi`
   + `tail`. $0 LLM cost during training. Wakes on death/anomaly.
6. **Review** — `/post-run-review` skill emits `{is_buggy,
   failure_class, summary, metric, lower_is_better}`.
7. **Close** — `journal.py close`, `calibration.py close`, emit
   `[LEARN]` (if bug) or `[DEAD-END]` (if bad hypothesis).
8. **Commit** — `/clean` writes sentinel; pre-commit-gate honors it;
   commit succeeds.
9. **Loop** — back to (1).

### When the agent gets stuck

- Stuck detector flags loops via stderr nudge.
- Anti-burn cooldown (in autopilot loop) exponentially backs off
  after consecutive failures, ntfy-wakes the human at threshold.
- `/propose-harness-change` is the legitimate path if the issue is
  the harness itself.
- The Update role (human) decides when stuck-state becomes a real
  issue requiring intervention.

### Self-improvement

- Agent emits `[LEARN harness-upstream] <improvement>` during
  ordinary work.
- Stop hook captures it with category=`harness-upstream`.
- User later runs `/propose-harness-change` → Generator (working
  agent) writes patch + rationale → Verifier (fresh-context Agent
  tool dispatch) audits → Updater (human) reviews + opens PR.
- The agent never auto-pushes. Editing the Verifier's own dispatch
  prompt is explicitly refused (canonical self-improvement footgun).

## Where the journeys meet

The researcher and agent both rely on:
- The session report being truthful (env, providers, queue, journal)
- The hook chain firing in registered order
- `[LEARN]` and `[DEAD-END]` blocks being durable across sessions
- Provider state being reconciled (not estimated)
- Hard rules being enforced, not advised

When either journey breaks, the failure mode is almost always:
**the harness made conscientiousness optional when it should have
made skipping expensive.**
