<!-- META:idastone-construction -->
# Roadmap — outstanding work, prioritized

Updated 2026-04-27. Re-rank when reality changes.

## The next sprint — AGENTS.md + manifest gate (highest leverage)

The 2026-04-27 dogfood revealed the harness's biggest current hole:
agents launch experiments in environments they don't understand,
sometimes on the wrong hardware. The fix is two-mechanism per
[Levanter pattern](https://github.com/stanford-crfm/levanter):

**Mechanism A — documentation contract:** information must EXIST in
a discoverable place.

- [ ] Adopt `AGENTS.md` at repo root (industry standard, not invented).
      Levanter is the reference. Replaces the proposed-but-not-built
      MO.md.
- [ ] Ship `agents-md-templates/{ml-research, web, security}.md`.
- [ ] Add `.playbooks/<task>.md` directory + skill that loads the
      relevant playbook before launch.
- [ ] Add `docs/Getting-Started-<HW>.md` per accelerator (the
      Levanter Getting-Started-GPU.md / Getting-Started-TPU-VM.md
      pattern). Each says: previous experiments that ran on this
      hardware, environment specifics, common gotchas.
- [ ] Add `docs/footguns.md` (lm-eval-harness pattern).

**Mechanism B — launch-time enforcement:** information must BLOCK
launches that would skip it.

- [ ] Per-experiment `manifest.json` requirement. Fields:
      `{git_sha, hardware_id, env_lockfile_hash, config_snapshot,
      seed, dependencies}`. `journal.py close` refuses to mark
      `done` without one. Existing runs grandfathered.
- [ ] `pre-train-gate.sh` extended: when launching a script
      referenced by a queue item with `parent_experiment_id`,
      reads the parent's `manifest.json`, refuses if `hardware_id`
      differs. Override via `--ignore-hardware-parity` with a
      mandatory rationale string.
- [ ] `queue.py preflight <id>` — parses queue item notes for
      `script:`, `data:`, `checkpoint:` references; verifies all
      exist locally; refuses claim if any missing.

This sprint is **2 weeks** of work realistically. It catches the
exact failure that wasted a session today.

## Tier A — same-day wins, after the sprint

Each is S effort, high leverage:

- [ ] `[LEARN] paper-controls: hardware-parity` rule emitted to user's DB
- [ ] A4 three-mode search policy (AIDE `agent.py` L60-92, MIT) —
      60 LOC + prompts. The journal tree (B1, shipped) is dead
      weight without this.
- [ ] B7 `/replan` skill — smolagents L541 pattern. Pairs with
      stuck-detector.
- [ ] B6 bias-probe panel reviewer — new /deploy-team template
      (pos/neg + meta). Sakana v1 pattern reimplemented.
- [ ] C4 failure-class upgrade — adopt arXiv 2603.06847's
      13-category enum as second column alongside the 3-value
      pre-classifier.

## Tier B — week-scale, after Tier A

- [ ] B2 VLM plot reviewer (Sakana v2 pattern reimpl)
- [ ] B8 persona-parallel waterfall (STORM ThreadPoolExecutor pattern)
- [ ] Anthropic three-agent harness (planner/generator/evaluator +
      context-reset, not compaction) — from 60-day research scan.
      `/deploy-team` already supports the team shape; this adds
      the sprint-contract artifact.
- [ ] File-as-Bus workspace-map (AiScientist pattern; arXiv
      ablation: -31.82pts on MLE-Bench Lite without it)
- [ ] HCC three-tier memory (HCC ablation = 56.44% medal rate on
      MLE-Bench at 24h budget)
- [ ] Hindsight four-network memory (LongMemEval 83.6% vs 39%)

## Tier C — strategic, multi-week

- [ ] C1 staged macro-workflow (Sakana v2 4-stage state machine
      above the waterfall, reimpl)
- [ ] C2 checkpoint/resume as JSON (free post-B1 — DB IS the
      checkpoint)
- [ ] C3 best-so-far code pool CLI (schema shipped)
- [ ] C5 Semantic Scholar novelty loop (Sakana v1 reimpl)
- [ ] AgentRxiv-style embedding retrieval (parallel index to FTS5,
      proven 73→78% multi-run improvement)
- [ ] GVU operator separation runtime (currently /propose-harness-change
      has the SKILL.md; runtime needs implementing)
- [ ] workflow.db ↔ memory.db promotion bridge

## Provider arbitrage — separate parallel sprint

Owned by the gpu-arbitrage agent (see `docs/_internal/gpu-arbitrage-agent-prompt.md`):

- [x] `providers/base.py` Protocol + dataclasses
- [x] `providers/runpod.py` refactor of CLI into class
- [x] `providers/vast.py` (spec §A)
- [ ] `providers/primeintellect.py` (spec §B — pending account)
- [x] ~~`providers/shadeform.py`~~ — **DROPPED 2026-04-27** (no spot tier, redundant upstream coverage; see `docs/_internal/market-research/SYNTHESIS.md`)
- [x] `providers/datacrunch.py` — Verda Cloud (replaces what shadeform.py would have given us, with a real spot tier)
- [x] `gpu.py` router with cooldown + on-demand gate
- [x] Migration 004: `preemption_events` (renumbered from 003 after fix migration 003 added gpu_pods.project)
- [x] Per-provider account-setup docs (`docs/providers-setup.md`)

Status as of 2026-04-27: in flight; budget-reconcile.sh + .env.example
already updated to expect `gpu.py reconcile`.

## Credibility artifacts — required before public launch

These convert idastone from "alpha" to "trustable" in OSS terms.

- [ ] MLE-bench Lite submission (target AIDE-current-champion
      comparison)
- [ ] Reproduce one famous paper end-to-end via the harness;
      ship the asciinema
- [ ] "Catches a real bug" blog post (top-10 [LEARN] entries from
      saml212's actual research)
- [ ] Bug-catch-rate benchmark vs AIDE/Sakana (intentionally-broken
      training scripts; measure GPU-minutes wasted before catch)
- [ ] Failure-taxonomy dataset (after C4 upgrade lands)

## Always-pending background work

- [ ] Keep CHANGELOG.md current per release tag
- [ ] Smoke test stays green
- [ ] /clean stays effective (audit.py false-positive list current)
- [ ] License gate run on every new vendor candidate
- [ ] Re-check "ecosystem gap" claims quarterly (failure-taxonomy
      claim went stale in Feb-Apr 2026)

## Schedule shape

| Week | Theme |
|---|---|
| 0 (now) | AGENTS.md + manifest gate sprint begins |
| 2 | Sprint ends; Tier A starts |
| 4 | Tier A done; Tier B begins; first credibility artifact (blog post) draft |
| 8 | Tier B done; MLE-bench submission |
| 12 | Tier C starts; provider arbitrage merged; public launch consideration |

## Decision criteria for next item

When you finish something, pick the next thing using:

1. Does it close a known failure mode actually observed in dogfood?
   (highest priority)
2. Does it unblock something else? (B1 unblocked A4, C2, C3)
3. Is it small and S-effort? (prefer over M)
4. Does its source license allow vendoring? (MIT/Apache only;
   else clean-room reimpl)
5. Does it compose with existing differentiators or duplicate one?
   (duplicates rejected)

If a candidate fails (5), don't ship it even if (1)-(4) are green.
