<!-- META:idastone-construction -->
# Decisions — architectural choices and why

Append-only log. New decisions go at the bottom. Don't edit prior
entries — supersede them with a new entry that says "supersedes
DEC-NN."

---

## DEC-01: Name = idastone

**Date:** 2026-04-23
**Considered alternatives:** rigor, falsify, eureka, lodestone,
crucible, assay, cairn, atelier, autolab, codify
**Choice:** idastone
**Reasoning:** User wanted something Pebble-adjacent (rock-themed)
that suggested intelligence/autonomy/discovery without requiring
explanation. "rigor" was rationally correct but emotionally cold;
"eureka" was charming but cliché; "lodestone" required interpretation.
"idastone" is original, distinctive, and pronounceable.
**Constraints:** GitHub: saml212/idastone (private as of launch).

## DEC-02: Apache-2.0 license

**Date:** 2026-04-23
**Choice:** Apache-2.0
**Reasoning:** Compatible with vendoring from MIT and Apache-2.0
sources (the majority of competing OSS harnesses). Explicit patent
grant is meaningful for a research-tooling repo.

## DEC-03: Local-first, no vector DB

**Date:** 2026-04-23
**Choice:** SQLite + FTS5 for memory; no Chroma/Pinecone/Qdrant.
**Reasoning:** All competing harnesses reach for vector DBs. FTS5 +
BM25 with a strong-match gate (score < -4) is enough for our
prompt-injection use case. Local-only means no external service,
no API key beyond Claude. Embeddings can be added in parallel
later (AgentRxiv pattern in roadmap) but FTS5 stays canonical.

## DEC-04: Hooks live in tracked settings.json, not local

**Date:** 2026-04-23 (verified bug)
**Choice:** All hook registrations in `settings.json` (committed).
Permissions in `settings.local.json` (gitignored).
**Reasoning:** Hooks placed in `settings.local.json` silently do
not fire — verified by absence in hook.log. We split the file at
that boundary so hooks are reproducible across machines.

## DEC-05: Pin sqlite3 to /usr/bin/sqlite3

**Date:** 2026-04-23
**Choice:** Hardcode `/usr/bin/sqlite3` in every shell script.
**Reasoning:** Some platforms ship sqlite3 on PATH that lacks
FTS5. macOS `/usr/bin/sqlite3` always has it. Linux CI symlinks
`/usr/bin/sqlite3` → system sqlite3 in the workflow.

## DEC-06: PRAGMA trusted_schema=1 prepended to every CLI insert

**Date:** 2026-04-23 (FTS5 trigger learning)
**Choice:** Every sqlite3 invocation that writes to learnings,
dead_ends, or experiments prepends `PRAGMA trusted_schema=1;`.
**Reasoning:** Without it, FTS5 triggers raise "unsafe use of
virtual table" on inserts. This is a per-connection PRAGMA, so
it must be re-set every CLI call.

## DEC-07: FTS5 hyphen sanitization is load-bearing

**Date:** 2026-04-23
**Choice:** `load-relevant-rules.sh` strips hyphens from prompt
tokens before MATCH.
**Reasoning:** `matrix-arch` in MATCH is parsed as "matrix NOT
arch" — column-NOT-term semantics. Without sanitization, queries
silently invert. Smoke test asserts this behavior is load-bearing
(test #15).

## DEC-08: Two /deploy-team implementations ship

**Date:** 2026-04-23
**Choice:** Local Python (markdown-only output) + global Node
(worktrees + dashboard + intervention log).
**Reasoning:** Different use cases — Python for fast gauntlets,
Node for long-running interventionable runs. Both share template
JSONs.

## DEC-09: Pre-commit clean-hash sentinel scoped to own repo

**Date:** 2026-04-23 (audit fix)
**Choice:** `pre-commit-gate.sh` uses `pwd -P` to canonicalize
OWN_REPO; only enforces when `TARGET_REPO == OWN_REPO`.
**Reasoning:** macOS `/var/folders/...` symlinks to
`/private/var/folders/...`. Without canonicalization, gate
falsely claimed "different repo" and skipped. Without scope
inversion, gate enforced when no git repo at all (TARGET empty
treated as match).

## DEC-10: Apply_patch.py refuses absolute and ../ paths

**Date:** 2026-04-23 (security audit C-1)
**Choice:** `apply_patch.py` resolves each target path against
cwd; rejects absolute and any path that escapes via `..`.
**Reasoning:** LLM-generated patches are the intended caller.
Without containment, a patch targeting `/etc/hosts` succeeds.
Hard-coded refusal — no `--allow-outside-cwd` flag exists.

## DEC-11: Autopilot.conf is parsed, not shell-sourced

**Date:** 2026-04-24 (security audit C-2)
**Choice:** `autopilot.conf` parsed with allow-listed key=value
reader; refuses `$(…)` and backticks; gitignored.
**Reasoning:** Original `. "$CONF"` made any committed
autopilot.conf an arbitrary-code vector. Parser approach
preserves the API while eliminating ACE.

## DEC-12: Dollars budget is the only enforced ceiling for Max users

**Date:** 2026-04-24
**Choice:** `.claude/budget.toml` for Max-subscription users
contains only `[project] dollars`. Tokens / wallclock / tool_calls
auto-tick but have no ceiling unless user opts in.
**Reasoning:** Claude Max has no per-token charge. The only real
external spend is GPU dollars. Capping tokens or wallclock would
artificially limit a paid resource.

## DEC-13: Spot bid defaults to minimum; never bumps

**Date:** 2026-04-24
**Choice:** `runpod.py create --bid` is optional. Default reads
`minimumBidPrice` from RunPod's lowestPrice query.
**Reasoning:** RunPod's spot is a blind auction — the floor IS
the scheduler's threshold. Paying above the floor doesn't
meaningfully reduce preemption probability. The right response
to preemption is provider-hopping (gpu.py router), not bid-
bumping. No `--bump` flag exists.

## DEC-14: Provider-hop > bid-bump > on-demand (not the inverse)

**Date:** 2026-04-24
**Choice:** Router order: try ranked spot providers (runpod →
vast → datacrunch → prime) at each provider's min; only with the
explicit `--allow-on-demand` flag do on-demand-only providers
engage. (As of 2026-04-27 the on-demand-only list is empty —
Shadeform was dropped, Verda's spot tier covers EU geography.
Flag stays for future on-demand additions.)
**Reasoning:** Different providers have different scheduler
states. A preemption on RunPod doesn't mean Vast has the same
shortage. On-demand providers charge ~2× spot floor. Treating
on-demand as fallback-of-last-resort costs less than treating it
as preemption-
recovery.

## DEC-15: Failure-taxonomy enum is 3-value pre-classifier, not novel

**Date:** 2026-04-24 (60-day research scan)
**Choice:** Keep `bug | bad-hyperparam | bad-hypothesis` as the
primary enum routing `[LEARN]` and `[DEAD-END]`. Add
arXiv 2603.06847's 13-category as a second column.
**Supersedes:** Earlier framing in PORTS.md / STARS.md that
called this an "ecosystem gap" — three 2026 papers closed it.
**Reasoning:** Three-value coarse classification is sufficient
to route between [LEARN] and [DEAD-END] capture. The 13-category
gives richer post-run analysis for human readers without changing
the routing logic.

## DEC-16: SessionStart hook output via JSON envelope, not stderr

**Date:** 2026-04-26 (live-session diagnosis)
**Choice:** `session-report.sh` outputs JSON envelope:
`{hookSpecificOutput: {hookEventName: SessionStart,
additionalContext: <text>}}` on stdout.
**Reasoning:** Claude Code's SessionStart hooks treat stderr as
banner text shown to the human, NOT as agent context.
UserPromptSubmit hooks inject stderr into context (correct for
load-relevant-rules), but SessionStart hooks need the
`additionalContext` field. Verified via the agent failing to
see the report despite the hook firing 3 times.

## DEC-17: AGENTS.md is the canonical contract, not invented MO.md

**Date:** 2026-04-27 (repo-organization research)
**Choice:** Adopt `AGENTS.md` at repo root as the universal agent
contract. CLAUDE.md remains for Claude-specific overrides.
**Supersedes:** Earlier proposal to invent `MO.md`.
**Reasoning:** [agents.md](https://agents.md/) is a ratified
standard adopted by Codex, Cursor, Claude Code, Jules, Factory,
Amp. Modern agents auto-read it walking up from cwd. Inventing
our own would forfeit free interop.

## DEC-18: Per-experiment manifest.json is the hardware-parity gate

**Date:** 2026-04-27 (live-session failure)
**Choice:** Every experiment produces `experiment-runs/<id>/manifest.json`
with `{git_sha, hardware_id, env_lockfile_hash, config, seed,
dependencies}`. `pre-train-gate.sh` reads parent's manifest when
launching a control; refuses if hardware_id differs.
**Reasoning:** A control experiment running on different hardware
is not a valid control. The agent's first instinct (save $0.70 by
using A100 for an H100-historical control) was wrong; only manifest-
gated enforcement prevents the same mistake from recurring. See
`LESSONS.md` entry 2026-04-27.

## DEC-19: docs/_meta/ committed, docs/_internal/ gitignored

**Date:** 2026-04-27
**Choice:** Two parallel "internal-flavored" directories.
`docs/_meta/` is committed and is for harness-construction agents
(this directory). `docs/_internal/` is gitignored and is for
user-confidential roadmap / positioning / unreleased material.
**Reasoning:** Future agents working on idastone need
PHILOSOPHY.md / DECISIONS.md / etc. to be in the OSS repo.
Per-user roadmap docs (e.g. STARS.md) shouldn't be in the OSS
repo. Two folders, two visibilities.
