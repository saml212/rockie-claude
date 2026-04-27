<!-- META:idastone-construction -->
# Plan — current snapshot of in-flight work

Updated 2026-04-27. This file is the most volatile in `docs/_meta/`;
expect it to drift. When in doubt, trust `git log` over this file.

## What's running right now (background agents)

### gpu-arbitrage agent (independent session)
- Working in `~/Experiments/idastone`
- Following the spec at `docs/providers-impl-spec.md`
- Following the prompt at `docs/_internal/gpu-arbitrage-agent-prompt.md`
- Already landed: `.env.example` extended with VAST/PRIME/SHADEFORM keys;
  `budget-reconcile.sh` updated to call `gpu.py reconcile`;
  `runpod.py` partially refactored toward `providers/runpod.py:RunPodProvider`
  shape (CLI is now a thin wrapper).
- In progress: `providers/base.py`, `providers/{vast,prime,shadeform}.py`,
  `gpu.py` router, migration 003.
- User pairs with this agent on API keys.

### Repo-organization research (returned 2026-04-27)
- Findings landed in `docs/_meta/LESSONS.md` (sources) and informed
  `DECISIONS.md` DEC-17 (AGENTS.md) and DEC-18 (manifest.json gate).
- Recommends Levanter as the reference architecture.

## Mid-flight, paused

### learned-representations Control A experiment
- Status: blocked
- Why: pre-flight discovered Round 4 didn't save checkpoints + ProsQA
  data lives on a dead pod. Agent proposed re-run-Round-4 +
  Control-A in 3 GPU-h. User asked about env parity, agent
  re-checked, pod preempted again, agent paused on the
  on-demand-vs-spot decision.
- Net: spot preemption storm + missing prerequisites both surfaced
  the AGENTS.md gap simultaneously. Re-attempt deferred until the
  AGENTS.md sprint lands so the next attempt fails earlier (at
  preflight, not after a pod is provisioned).

## Currently-EXITED RunPod state

- Pod `uqzsjvlhbx34p5` (idastone-dogfood-spot) — first attempt; EXITED.
- Pod `3ggrdxb3m22wt4` (idastone-dogfood-spot) — second attempt;
  preempted in < 5 min on H100 SXM at $1.50.
- Both still incurring volume storage charges (~$0.13/day combined).
- User can `runpod.py terminate <id> --yes` to stop accrual; current
  cost should be < $1 cumulative.

## Next-up items (in priority order)

These are the things that should be picked up next, by whichever
agent has bandwidth.

1. **Wait for gpu-arbitrage agent's first deliverable** — `providers/base.py`
   + `providers/runpod.py`. Once those land, RunPod CLI is plumbed
   through the new abstraction without behavior change.
2. **Start the AGENTS.md sprint** (`ROADMAP.md` top item) — write the
   AGENTS.md template, the ml-research preset, and the `.playbooks/`
   directory before doing the manifest.json work.
3. **Manifest.json + journal close gate** — once schema is decided,
   migration + `journal.py close` validation + `pre-train-gate.sh`
   parent-manifest hardware check.
4. **Retroactively write a manifest** for Round 4 vanilla SFT runs
   so Control A's parent has something to be checked against.

## Decisions blocked on user

- DEC pending: ack scope (per-session vs per-day) for AGENTS.md reading enforcement.
  My lean: per-session for hard gates, per-launch for verifier gates,
  no ack for the inline-everything path.
- DEC pending: trust-or-verify ack — verify via transcript-opened-files
  is more code, trust is faster. My lean: trust the soft acks, verify
  the hard ones (manifest hardware match, checkpoint existence).

## Things to clean up after this session

- Stale `docs/_internal/` content if any
- The two EXITED RunPod pods (user's call to terminate)
- This PLAN.md itself — should get rewritten as items move forward
- Possibly delete `docs/STARS.md` reference from the original
  scaffold commits (it was moved to `docs/_internal/stars.md` later)

## Invariants to preserve

- Smoke test stays green (`bash tests/smoke-test.sh` → 69+ assertions pass)
- CI smoke workflow stays passing on Ubuntu free tier
- `runpod.py` CLI as the live agent uses it today keeps working
  (don't break entry points; refactor underneath)
- License gate discipline (no GPL or restrictive-license code vendored)
- Hard rules (PHILOSOPHY.md) stay enforced
- Composition rules respected (no duplicates of existing
  differentiators)
