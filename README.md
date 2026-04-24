# idastone

**The autonomous research harness that catches bugs before you burn GPU
time, notices when it's stuck, tracks whether its predictions were
right, and tells you honestly whether the idea was wrong or just the
implementation.**

A Claude Code + Claude Agent SDK harness for autonomous ML research.
Hooks install into your project; your agent gains a pre-run audit
loop, a durable `[LEARN]` memory, a queryable dead-ends registry, an
agent-team orchestrator, and an ntfy push channel — all local, all
SQLite, no API keys except Claude.

> Status: **alpha / pre-launch.** The harness is running in production
> on an 8×H100 autonomous research project. This repo packages it for
> the community. Breaking changes until `v0.1`.

---

## Why idastone

Four gaps nobody else in this space has closed. We close all four:

| Gap | How idastone closes it |
|---|---|
| **Pre-run code audit** — every other harness reviews *after* a run burns compute | A separate auditor agent reads shapes/gradients/stability *before* launch; `/clean` sentinel + pre-commit-gate hook refuse to commit unexamined diffs |
| **Semantic-loop detection** — agents spin silently for hours | Port of OpenHands `stuck.py`: 4 loop types (action-repeat, error-repeat, monologue, alternating-cycle at periods 2/3/4). The 5th OpenHands type, `condensation-loop`, is specific to their context-compressor and does not translate to Claude Code's transcript model — documented in `docs/PORTS.md`. |
| **Hypothesis calibration** — nobody tracks whether predictions were right | Every experiment logs `predicted_delta` + `actual_delta`; the `[LEARN]` DB surfaces whether your priors are improving |
| **Failure taxonomy** — harnesses lump bugs, bad hyperparams, and bad hypotheses | Post-run review emits a 3-value classification; future `[LEARN]` recall filters on it |

See [docs/PORTS.md](docs/PORTS.md) for source-level citations to every
competing harness we read.

## The loop

```
                  ┌─ Plan ─────────────────────────── user talks to Claude
                  │
                  ├─ Research ──── send agents to verify, check novelty
                  │
                  ├─ Build ─────── write code, clean, comment the non-obvious
                  │
                  ├─ Audit ─────── SEPARATE agent reviews: shapes, gradients, stability
                  │                (this is the pre-run gate nobody else has)
                  │
                  ├─ Run ───────── execute; ntfy push on preemption / block / win
                  │
                  ├─ Assess ────── post-run review emits {is_bug, bad-hyperparam, bad-hypothesis}
                  │
                  └─ Codify ────── emit [LEARN] block → auto-saved to workflow.db
                                   (FTS5-indexed; next prompt auto-injects relevant rules)
```

Every cycle should make the next cycle better.

## Install

```bash
git clone https://github.com/saml212/idastone.git ~/idastone
cd ~/idastone
./install.sh ~/path/to/your/research-project
```

(The target project argument is required when the clone *is* your working
directory — without it the installer refuses to install idastone into its
own clone.)

The installer:

1. Copies `project-harness/` into `<your-project>/.claude/`
2. Copies `user-harness/` into `~/.claude/` (hooks, memory lib, team orchestrator)
3. Initializes `workflow.db` via `/usr/bin/sqlite3` (FTS5 required)
4. Seeds generic harness rules (see `project-harness/scripts/seed_hard_rules.py`)
5. Prints a CLAUDE.md template path — you drop it into your project root and edit the `Project` section.

See [docs/install.md](docs/install.md) for manual install and [docs/ntfy-setup.md](docs/ntfy-setup.md) for the push-notification setup (optional).

**Verify the install works on your box** — `bash tests/smoke-test.sh` runs
47 assertions (hook fires, FTS5 searches, atomic queue claim, installer
idempotency, path-traversal refusal, budget-ceiling enforcement). CI runs
the same suite on every push. ~10 seconds, no API key.

## What gets installed

Into your project's `.claude/`:

- **hooks/** — `learn-capture` (Stop), `load-relevant-rules` (UserPromptSubmit), `correction-detect`, `doc-guard` (PreToolUse Write/Edit), `pre-commit-gate` (PreToolUse Bash)
- **skills/clean/** — pre-commit anti-slop audit that writes a sentinel for the gate hook
- **skills/deploy-team/** — Python orchestrator for multi-agent teams (gauntlet / pre-launch-audit / post-run-analysis templates)
- **memory/schema.sql** — FTS5 learnings DB + sessions + notifications
- **scripts/** — `notify.sh` (ntfy push), `ntfy_poll_responses.sh`, `compute_clean_hash.sh`, `rotate_hook_log.sh`, `seed_hard_rules.py`, `init_db.sh`

Into `~/.claude/`:

- **hooks/** — `memory-session-start` (surfaces rules into `rules-compiled.md`), `memory-pre-compact` (rescues unsaved `[LEARN]` blocks), `check-orphan-dashboards`
- **skills/deploy-team/** — global skill definition
- **teams/** — Node/Express orchestrator with live dashboard + git worktrees per agent (for bigger `/deploy-team` runs)
- **scripts/memory/** — cross-repo memory lib (tier-promoted rules across projects)

## The `[LEARN]` protocol

When Claude learns something durable, it emits:

```
[LEARN] <category>: <one-line rule>
Mistake: <what went wrong>
Correction: <what the right approach is>
```

The Stop hook parses these out of the assistant turn, dedupes by
`(project, category, rule)`, and inserts into `.claude/memory/workflow.db`.

On the next prompt, the UserPromptSubmit hook tokenizes the prompt,
runs an FTS5 BM25 search over the learnings, and injects the top-5
relevant rules into Claude's context — but only if the best match is
genuinely strong (BM25 score < -4). No noise.

## CLAUDE.md templates

Presets in `claude-md/`:

- `CLAUDE.md.template` — generic baseline
- `ml-research.md` — ML/AI research preset (includes pre-experiment checklist specific to training runs)

Add your own and PR them.

## Licensing

Apache-2.0. See [LICENSE](LICENSE).

Ports from other open-source harnesses are credited in
[docs/PORTS.md](docs/PORTS.md). We only vendor code from Apache-2.0 /
MIT-licensed repos; patterns from restrictively-licensed harnesses are
clean-room reimplemented.

## Contributing

- Every port must cite source file + line range.
- Every new feature must compose with the existing differentiators
  (pre-run audit, `[LEARN]` DB, waterfall, living-doc pattern,
  experiment-runs/, `/deploy-team`, pre-commit sentinel). Duplicates get
  rejected.
- Run `/clean` before committing — the pre-commit-gate hook enforces it.

**Upstream-back from agents:** if an agent using idastone in your own
project discovers a harness-level improvement, it can emit
`[LEARN harness-upstream] …` during the session. Run
`/propose-harness-change` later to package the improvement as a
reviewed, verified patch (Generator/Verifier/Updater split — the agent
never auto-pushes). See `project-harness/skills/propose-harness-change/SKILL.md`.

## Environment variables

Secrets (RunPod API key, ntfy topic, future provider keys) live in a
gitignored `.env` file at the project root. Copy `.env.example`, fill
in values, and load with `set -a; . .env; set +a`. See
[docs/environment.md](docs/environment.md) for the full list of
supported vars and rotation guidance.

## Further reading

- [docs/quickstart.md](docs/quickstart.md) — 5-minute install + first commands
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — event flow + storage model
- [docs/PORTS.md](docs/PORTS.md) — every competitor we read, source-cited
- [docs/ntfy-setup.md](docs/ntfy-setup.md) — push notifications setup
- [SECURITY.md](SECURITY.md) — threat model + risk surfaces
- [CHANGELOG.md](CHANGELOG.md) — what changed, by release
