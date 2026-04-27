<!-- META:idastone-construction -->
# Philosophy — what idastone is and is not

## High-level goals (mirrored to user-facing README)

idastone is **the autonomous research harness that catches bugs before
you burn GPU time, notices when it's stuck, tracks whether its
predictions were right, and tells you honestly whether the idea was
wrong or just the implementation.**

It is built around a **7-step research loop** that every cycle should
make better:

```
Plan → Research → Build → Audit → Run → Assess → Codify
```

The harness's job is to make the loop reliable enough to run for
days without human input, while staying honest about what it doesn't
know.

## The four ecosystem gaps idastone closes

These are the unique differentiators — the load-bearing pitch.
Anything that duplicates these gets rejected (see CONTRIBUTING.md).

1. **Pre-run code audit.** Every other harness reviews after a run
   burns compute. idastone audits *before* — `/deploy-team
   pre-launch-audit` + `/clean` sentinel + pre-commit-gate hook.
2. **Semantic-loop detection.** Agents spin silently for hours
   elsewhere. We port OpenHands's `stuck.py` taxonomy (4 loop types,
   periods 2/3/4) and inject a `[LEARN]` + `/replan` proposal.
3. **Hypothesis calibration.** Nobody else tracks predicted vs
   actual metric deltas. Our scorecard surfaces whether the agent's
   priors are improving or drifting.
4. **Failure taxonomy.** No one else cleanly separates `bug |
   bad-hyperparam | bad-hypothesis`. Post-run review enforces it; the
   `[LEARN]` and `[DEAD-END]` pipelines route on it.

(Caveat: as of 2026-04, three arXiv papers — 2603.06847, 2602.21806,
2604.17658 — closed the failure-taxonomy gap with richer schemas.
We're still differentiated on the 3-value coarse pre-classifier
feeding `[LEARN]/[DEAD-END]` routing, but the "nobody owns this"
framing is stale. See `LESSONS.md`.)

## What idastone IS

- **A Claude-Code-native composition of hooks, skills, and SQLite.**
  Not a runtime, not a framework, not an orchestration DSL. Hooks
  live in your `settings.json`. Reversible in 5 seconds.
- **Local-first.** All state in SQLite + filesystem. No vector DB.
  No external service except Claude itself and (optionally) ntfy
  for push and external GPU providers for compute.
- **Plug-and-play installable.** `./install.sh <project>` merges
  into the user's existing setup non-destructively.
- **Self-improving with guardrails.** `[LEARN]` and `[DEAD-END]`
  blocks accumulate durable knowledge in workflow.db. The
  `/propose-harness-change` skill packages improvements as PRs back
  to upstream idastone via Generator/Verifier/Updater role-separation.
- **Provider-portable for compute.** `runpod.py` exists today;
  `gpu.py` extends to Vast/Verda/Prime with cooldown-driven hopping.
  Spend tracked against truthful provider state, not
  estimates.

## What idastone IS NOT

- **Not a paper-writing system.** We deliberately reject Sakana-style
  full LaTeX writeup pipelines. Out of scope.
- **Not a sandbox.** smolagents-style AST executors are not real
  sandboxes. We don't pretend.
- **Not a GPU-aggregation business.** Prime / SkyPilot / Foundry
  already commoditize that. Our value is autonomy reliability, not
  routing margin.
- **Not multi-provider for the LLM** (yet — single-provider Claude
  by default, multi-provider is an open roadmap item).
- **Not a replacement for `experiment-runs/` archival convention.**
  We extend it (manifests, journal nodes) — not replace.

## Composition rules

Every new feature must compose **with** these existing pieces, not
replace them. Duplicating any of them is grounds for PR rejection:

- Pre-run audit agent (uniquely ours)
- FTS5 `[LEARN]` DB with prompt-time injection
- Waterfall (Brainstorm → Research → Attack → Validation)
- Pre-experiment checklist
- ntfy.sh preemption recovery
- Living-doc pattern (STATE / ARCHITECTURE / EXPERIMENT_LOG)
- `experiment-runs/` archived scripts per run
- `/deploy-team` (Python local + Node global)
- Pre-commit sentinel gate
- doc-guard hook (anti-slop)
- Dead-end registry
- Hypothesis calibration
- Stuck detector
- Experiment queue with atomic claims
- Journal tree (AIDE-style)
- Budget controller with auto-tracking
- ZCM (zero-cost monitor)

## Hard rules (the things that never bend)

These came from real failures. They're enforced (where mechanizable)
or socially required (where not).

1. **Verify before claiming.** Use research agents or web search.
   Never assert facts without evidence.
2. **Audit before running.** A separate agent reviews — implementer
   does not review their own work.
3. **Smoke test before training.** Forward, backward, gradient
   check, eval batch size included.
4. **License gate before vendoring.** `gh repo view --json
   licenseInfo`. Custom licenses → reimplement patterns, don't copy
   code.
5. **Save the exact script alongside results.** Reproducibility
   requires the actual code, not a description.
6. **Pin sqlite3 to `/usr/bin/sqlite3`.** PATH defaults sometimes
   lack FTS5.
7. **Hooks live in `settings.json`, not `settings.local.json`.**
   Hooks placed in `.local` do not fire.
8. **Dead directions stay dead.** Don't revisit archived ideas
   unless explicitly asked.
9. **Spot bids start at minimum.** Provider-hop on preemption,
   never bump bid on the same provider.
10. **No Co-Authored-By Claude trailers** in commit messages
    (project-specific user preference).
11. **Don't overprompt.** Trust the harness to onboard the agent
    via SessionStart hook + canonical docs. Hand-written
    "here's what to do tonight" playbooks defeat the harness.

## Crossover doctrine — restated

The four-gap pitch, the 7-step loop, and the differentiator list are
the **only** sections that appear in both meta and user trees.
Everything else stays in its lane.
