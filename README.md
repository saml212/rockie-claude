# rockie

**An Autonomous AI research assistant that rocks.**

Inspired by Project Hail Mary's Rocky — the alien research partner you
couldn't have built the answer without.

---

## What rockie does for you

Four jobs, run continuously, until you tell it to stop:

### 1. Captures your research taste — and iterates on it

A 5-minute first-run interview compiles your worldview, methodology,
dismissals, and voice into a durable `.rockie/taste/` corpus. Every
future session loads it automatically. Your agent knows what *you*
think a good result looks like, what dead ends you've sworn off, and
what register you want it to write in. Refresh anytime with
`/onboard --section <name>`. Voice-first deep mode for laddering.

### 2. Bulletproofs every step with adversarial subagent networks

Plan → Research → Build → Audit → Run → Assess → Codify. Each step has
adversarial review built in:

- **`/deploy-team`** — gauntlets (brainstorm / research / attack / validate),
  pre-launch audits, post-run analysis. A team of agents fight over
  every important call.
- **`/clean`** — pre-commit anti-slop audit gates `git commit` until
  debug artifacts and stale claims are gone.
- **`/propose-harness-change`** — Generator / Verifier / Updater split.
  The agent never auto-pushes.
- **stuck-detector + hypothesis calibration + dead-end registry** —
  background services that nudge the agent when it's spinning, when
  its priors are drifting, when it's about to re-propose a dead idea.

### 3. Cheap, resource-efficient autonomy — indefinitely

- **Local-first.** SQLite + FTS5 `[LEARN]` memory. No vector DB. No
  service except Claude itself.
- **Claude Max friendly.** Tokens/wallclock/tool-calls auto-tracked
  but uncapped (they cost nothing). Only GPU dollars get enforced
  ceilings.
- **Spot-first GPU policy.** Min-bid defaults. Provider-hop on
  preemption (RunPod / Vast / Prime / Verda) before ever bumping a
  bid. On-demand last resort, gated.
- **Modes** — `/mode switch paper-crunch` for deadline-locked
  scope-lock + Opus-on-attack; `/mode switch exploratory` for broad
  reading + sonnet-first speed; build your own. Swap operational
  policy without changing your identity.

### 4. Stays honest

- Catches bugs *before* you burn GPU time (separate auditor agent
  reads shapes/gradients/stability pre-launch).
- Notices when it's stuck (4 semantic-loop types, periods 2/3/4).
- Tracks whether predictions were right (`predicted_delta` vs
  `actual_delta` per experiment).
- Classifies every failure: `bug | bad-hyperparam | bad-hypothesis`.
  Routes `[LEARN]` and `[DEAD-END]` accordingly.

> Status: **alpha / pre-launch.** Running in production on an 8×H100
> autonomous research project. This repo packages it for the
> community. Breaking changes until `v0.1`.

---

## The loop

```
                  ┌─ Plan ─────────── you talk to Claude
                  │
                  ├─ Research ─────── subagents verify, check novelty
                  │
                  ├─ Build ────────── write code, clean, comment the non-obvious
                  │
                  ├─ Audit ────────── SEPARATE agent reviews shapes/gradients/stability
                  │                   (the pre-run gate nobody else has)
                  │
                  ├─ Run ──────────── execute; ntfy push on preemption / block / win
                  │
                  ├─ Assess ───────── post-run review emits {is_bug, bad-hyperparam, bad-hypothesis}
                  │
                  └─ Codify ───────── [LEARN] block → workflow.db (FTS5)
                                      next prompt auto-injects relevant rules
```

Every cycle should make the next cycle better.

---

## Install

```bash
git clone https://github.com/saml212/rockie.git ~/rockie
cd ~/rockie
./install.sh ~/path/to/your/research-project
```

The installer:

1. Copies `project-harness/` → `<your-project>/.claude/`
2. Copies `user-harness/` → `~/.claude/`
3. Initializes `workflow.db` (FTS5 required — pinned to `/usr/bin/sqlite3`)
4. Seeds harness rules + 5 mode templates (default, paper-crunch,
   exploratory, dogfooding, learning)
5. Prints a `CLAUDE.md` template path to drop into your repo root.

**On first session:** SessionStart hook prompts you to run `/onboard`
— 5–7 questions, ~5 minutes, voice optional. Produces your taste
corpus.

**Verify the install:** `bash tests/smoke-test.sh` runs 75+ assertions
(hooks fire, FTS5 search, atomic queue claim, installer idempotency,
path-traversal refusal, budget-ceiling enforcement, autopilot
end-to-end with mock launcher, schema migrations, autopilot.conf safe
parser, GPU router with fake providers). CI runs the same on every
push. ~10 seconds, no API key.

See [docs/install.md](docs/install.md) for manual install,
[docs/quickstart.md](docs/quickstart.md) for first-session walkthrough,
[docs/ntfy-setup.md](docs/ntfy-setup.md) for push notifications
(optional).

---

## The skills you'll invoke

| Skill | What |
|---|---|
| `/onboard` | researcher-taste interview → six-file `taste/` corpus that auto-loads every session |
| `/mode` | swap operational overlays (paper-crunch / exploratory / dogfooding / learning / your own) |
| `/deploy-team` | dispatch adversarial subagent gauntlets — Python local + Node global with worktrees |
| `/clean` | pre-commit anti-slop audit + sentinel; gates `git commit` |
| `/propose-harness-change` | package an upstream-back patch with Generator/Verifier/Updater review |
| `/queue-refill` | brainstorm 3–5 new high-quality experiments when the queue runs dry |
| `/post-run-review` | structured review after every training/eval run; emits `[LEARN]` or `[DEAD-END]` |
| `/autopilot` | continuous-operation mode for days-long autonomous work |

---

## The `[LEARN]` protocol

When Claude learns something durable mid-session, it emits:

```
[LEARN] <category>: <one-line rule>
Mistake: <what went wrong>
Correction: <what the right approach is>
```

The Stop hook parses, dedupes by `(project, category, rule)`, inserts
into `.claude/memory/workflow.db`. On the next prompt, the
UserPromptSubmit hook tokenizes the prompt, runs an FTS5 BM25 search
over the learnings, and injects the top-5 relevant rules — but only
if the best match is genuinely strong (BM25 score < -4). No noise.

---

## Licensing

Apache-2.0. See [LICENSE](LICENSE).

Ports from other open-source harnesses are credited in
[docs/PORTS.md](docs/PORTS.md). We only vendor MIT/Apache-2.0 code;
patterns from restrictively-licensed harnesses are clean-room
reimplemented.

## Contributing

- Every port must cite source file + line range.
- Every new feature must compose with existing differentiators (taste
  corpus, modes, pre-run audit, `[LEARN]` DB, waterfall, journal tree,
  experiment-runs/, `/deploy-team`, pre-commit sentinel). Duplicates
  get rejected. See [docs/_meta/PHILOSOPHY.md](docs/_meta/PHILOSOPHY.md).
- Run `/clean` before committing — the pre-commit-gate hook enforces it.

**Upstream-back from agents.** If an agent using rockie in your own
project discovers a harness-level improvement, it can emit
`[LEARN harness-upstream] …` mid-session. Run
`/propose-harness-change` later to package it as a reviewed,
verified PR. The agent never auto-pushes.

---

## Further reading

**For users:**

- [docs/quickstart.md](docs/quickstart.md) — 5-minute install + first commands
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — event flow + storage model
- [docs/budgets.md](docs/budgets.md) — 4-dimension auto-tracking
- [docs/environment.md](docs/environment.md) — `.env` + rotation
- [docs/ntfy-setup.md](docs/ntfy-setup.md) — push notifications
- [docs/self-hosted-runner.md](docs/self-hosted-runner.md) — Mac mini runner + PR review
- [docs/PORTS.md](docs/PORTS.md) — every competitor we read, source-cited
- [SECURITY.md](SECURITY.md) — threat model + risk surfaces
- [CHANGELOG.md](CHANGELOG.md) — what changed, by release

**For agents and contributors working on rockie itself:**

- [docs/_meta/README.md](docs/_meta/README.md) — meta-doc index (start here)
- [docs/_meta/PHILOSOPHY.md](docs/_meta/PHILOSOPHY.md) — what rockie is and is not
- [docs/_meta/USER_JOURNEYS.md](docs/_meta/USER_JOURNEYS.md) — researcher + agent flows
- [docs/_meta/FEATURES.md](docs/_meta/FEATURES.md) — built / partial / planned
- [docs/_meta/ROADMAP.md](docs/_meta/ROADMAP.md) — outstanding work, prioritized
- [docs/_meta/DECISIONS.md](docs/_meta/DECISIONS.md) — architectural decisions log
- [docs/_meta/LESSONS.md](docs/_meta/LESSONS.md) — durable user feedback + audit findings
- [docs/_meta/ONBOARDING_DESIGN.md](docs/_meta/ONBOARDING_DESIGN.md) — `/onboard` design spec
- [docs/_meta/PLAN.md](docs/_meta/PLAN.md) — current snapshot of in-flight work
