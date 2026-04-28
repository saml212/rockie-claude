<!-- META:rockie-construction -->
# Onboarding & TASTE.md design

Design spec for `/onboard` — the first-run interview that compiles a
researcher's intellectual taste into a durable, agent-injectable
artifact. This is rockie's marquee distinguishing feature: no other
research harness models the researcher.

Sister to AGENTS.md (project-level contract). Where AGENTS.md tells an
agent *what to do in this repo*, the `taste/` corpus tells an agent
*who this researcher is and how they think*. This is rockie's
fifth differentiator (see PHILOSOPHY.md): no other harness models
the researcher.

## Decisions (with sources)

### D1 — Schema: SOUL.md-extended, six files in `taste/`

```
.rockie/taste/
├── INDEX.md           # ~300 tokens, auto-injects every session
├── SOUL.md            # identity, worldview, hot takes  (SOUL.md compat)
├── STYLE.md           # written + spoken voice          (SOUL.md compat)
├── MEMORY.md          # append-only session log         (SOUL.md compat)
├── METHODOLOGY.md     # NEW: rigor standards, success criteria
└── DISMISSALS.md      # NEW: append-only dead ends, "never again"
```

Each file: YAML frontmatter (machine-parseable fields) + prose body.
Only `INDEX.md` auto-injects every session. Full files load on keyword
match via skill (`/taste-load methodology`) so the auto-inject tax stays
bounded.

**Why not monolithic.** Update granularity. METHODOLOGY shifts on a
different cadence than SOUL; mixing them forces full-file rewrites for
small changes and corrupts version-control deltas.

**Why not 12-field YAML.** Loses the prose richness that captures
hedging, hesitation, the surprising clause. SOUL.md got this right.

**Why this exact extension.** Research practice has two stable concerns
ordinary SOUL.md doesn't: the rigor standards by which a result is
judged true (METHODOLOGY) and the dead ends never to revisit
(DISMISSALS). Adding two files preserves community legibility — any
SOUL.md-aware agent reads rockie's identity layer for free, and
METHODOLOGY/DISMISSALS get upstream-back via `/propose-harness-change`
to the soul.md spec when they prove their worth.

Sources: aaronjmars/soul.md (template structure); SOUL.md/STYLE.md/MEMORY.md
schemas as published.

### D2 — Interview shape: two-tier

**Tier 1 (5–7 questions, text-first, ~5 minutes)** runs on first
invocation. Produces working stubs of all six files. Each question is
chosen so the answer changes downstream harness behavior:

1. *Identity stub* — "In one sentence: who are you and what brought
   you to the problem you're working on now?"
2. *Worldview anchor* — "Pick a contested take in your field where
   you'd bet money on a specific side. What's the take, and why?"
3. *Methodology anchor* — "What does a result need to look like
   before you'd believe it enough to publish it?"
4. *Dismissal anchor* — "Name one approach or class of ideas you've
   tried and won't revisit. Why did it fail?"
5. *Style anchor* — "When you read a paper that gets it right, what
   does it sound like? When it gets it wrong?"
6. *Compute / risk* — "What's a single experiment worth, in dollars
   or GPU-hours, before you'd want a sanity check first?"
7. *Heroes / anti-patterns (optional)* — "Whose work do you most
   admire, and whose do you most distrust, and why?"

**Tier 2 (20–30 minutes, voice-first, optional)** runs on
`/onboard --deep` or auto-triggers after first agent-researcher
disagreement. Uses MIRROR-style thoughts/memories/beliefs scratchpad
+ laddering until terminal values surface. Deepens each file from
its Tier 1 stub.

**Why two-tier.** The `gh auth login` / Astro pattern (5 fast questions,
each gating the next) is right for the install-time path: zero ceremony,
visible payoff. The SOUL.md conversation-not-form pattern is right for
deep extraction: laddering, discrepancy probing, surprising-clause
follow-up. Don't pick one; ship both with clear triggers.

Sources: arxiv 2506.00430 (MIRROR cognitive split); arxiv 2505.02709
(goal drift mechanics + strong elicitation); arxiv 2304.03442
(Generative Agents seed memory); UX laddering literature; Hanway 2021
(cognitive load on multi-question turns); aaronjmars/soul.md.

### D3 — Three-layer separation: AGENTS.md + CLAUDE.md + taste/

| Layer | File(s) | Scope | Update cadence |
|---|---|---|---|
| Project contract | `AGENTS.md` | repo | stable, edit on convention change |
| Claude-specific + volatile state | `CLAUDE.md` | repo | medium — current deadline, blocker, phase |
| Researcher identity | `taste/` | person | identity layer rare; MEMORY/DISMISSALS append-only |

**Volatile state goes in CLAUDE.md, not taste/.** Per-paper deadline,
current paper blocker, current pipeline phase — these are repo-state,
not personal identity.

### D4 — Update model: two-speed

- **Identity layer** (SOUL, STYLE, METHODOLOGY) — only-on-explicit
  refresh via `/onboard --redo` or `/onboard --section <name>`. No
  silent agent rewrites.
- **Append-only layer** (MEMORY, DISMISSALS) — agent-writable on
  session-end via existing Stop hook patterns. New entries cite
  evidence (a `[LEARN]` block, a closed experiment, a failed run).
- **Event-driven deltas with researcher confirmation** — deferred to
  Phase 2. The harness flags candidate deltas during a session ("the
  researcher just approved X they previously dismissed; propose
  DISMISSALS.md update?"); researcher confirms in batch at end.

### D5 — Voice: built-in `/voice tap` for Tier 2; Tier 1 stays text

Claude Code's built-in `/voice` (v2.1.116+) is zero-setup,
zero-dependency, sub-2-second latency, and uses Claude.ai auth (no
OpenAI key needed). Tier 1 stays text because it's short enough that
typed answers don't lose richness.

Tier 2 (long, exploratory, value-laddering) is where voice pays off.
The interviewer's system prompt tells the user: *"For deep questions,
use `/voice tap` — speak as long as you want."* The agent then treats
the voice transcript as a single rich answer turn. No homegrown
sox+Whisper pipeline shipped day-1 (deferred fallback).

## Interviewer prompt design

The system prompt for Tier 1 is in `prompts/interviewer-tier1.md` and
must satisfy these properties (each verified by the audit team):

1. **Strong goal elicitation** — first non-blank line restates the
   one-and-only objective. Re-injected every ~10 turns by the
   interviewer itself.
2. **Phase-gated state machine** — explicit topic list with 0/1/2
   coverage scoring. Cannot move past a topic until coverage ≥ 1; can
   stop the interview when all topics ≥ 2 OR seven Tier-1 questions
   asked.
3. **Thoughts / memories / beliefs scratchpad** — regenerated each
   turn (MIRROR), not appended to. Bounded ~500 tokens. Hidden from
   user.
4. **One question per turn discipline** — explicit rule + question-mark
   self-check on every output.
5. **Laddering trigger** — when the answer contains a value-laden word
   ("rigorous," "clean," "honest," "elegant") without unpacking, the
   next question asks "what does that give you?"
6. **SOFT-flag and move on** — dodged questions get marked SOFT in the
   memory scratchpad; do not press a second time.
7. **Surprising-clause hook** — if the user uses an unexpected word or
   pivots mid-answer, the agent's next reflection acknowledges that
   specific clause. (Terry Gross technique.)
8. **End condition** — agent-initiated when coverage met; user-confirmed
   via summary-and-correct round before files written.

## Compile step

After the interview, `runtime/compile.py` reads the interview JSON
(structured as `{topic: [{q, a, soft, ladder_chain}]}`) and produces
the six markdown files using `templates/`. The agent then opens each
in the user's editor for final review before saving to
`.rockie/taste/`.

Compile is deterministic — same JSON, same output. This means the
interview can be re-played, audited, or replayed in dogfood with
different researcher personas without leaking history.

## Install / SessionStart integration

- `install.sh` final message points at `/onboard` as the recommended
  next step (alongside the existing CLAUDE.md template instruction).
- SessionStart hook (`session-report.sh`) checks for
  `.rockie/taste/INDEX.md`; if absent, prepends one line to the
  hook output: *"No `taste/` corpus found. Run `/onboard` to set
  one up — 5 minutes, voice optional."*
- INDEX.md (when present) is included in the SessionStart additional
  context so every session starts with the researcher's identity loaded.

## What the audit team will look for

When `/deploy-team` runs the gauntlet on this design (see § next):

- **Brainstormer** — what's the strongest version of this we haven't
  considered? (e.g., embedding-retrieval over the taste corpus.)
- **Researcher** — does any 2026 paper invalidate the "regenerate
  scratchpad each turn" claim? Any open-source interview agent we
  should learn from?
- **Attacker** — failure modes. What if the user lies? Performs
  taste they don't have? Speaks differently than they type? What if
  the interviewer drifts into therapy-bot register and the user
  bails? What if six files is too many and the agent skips the ones
  it thinks aren't relevant, producing inconsistency?
- **Validator** — for each attack, do we have a mitigation, or is the
  attack accepted as known-limitation?

## Modes — small swappable overlays on the central corpus

Modes are how a researcher who works across multiple contexts (paper
deadlines, exploratory tinkering, teaching, neuroscience side
projects) tells the harness how *this session's* operational policy
differs from their stable identity.

**Identity is centralized.** SOUL/STYLE/METHODOLOGY/DISMISSALS/MEMORY
stay as one canonical corpus. The researcher does not split their
identity into per-area silos. (We considered profiles — see
discarded-design notes.)

**Modes are overlays.** A mode is a small TOML file at
`.rockie/taste/modes/<name>.toml`. The active mode is named in
`.rockie/taste/modes/_active` (one line, plain text). SessionStart
reads both and surfaces a compact summary alongside INDEX.md.

A mode CAN override specific fields (e.g.,
`methodology.success_criteria`, `risk.sanity_check_above_dollars`).
A mode CAN add operational fields not in the central corpus
(`workflow.scope_lock`, `deadline.target_date`,
`hardware.preferred_provider`).

A mode CANNOT override core identity (SOUL/STYLE entries) — that's
why those live in the central corpus.

### Mode TOML schema

Every field is optional. Modes ship lean.

```toml
name = "<short slug — matches filename>"
description = "<one sentence>"

[hardware]
preferred_provider = "runpod" | "vast" | "prime" | "verda"
hardware_type = "H100" | "A100" | "H200"
spot_only = true | false
on_demand_allowed = true | false
gpu_budget_dollars_per_session = 50

[reading]
focus_arxiv_categories = ["cs.LG", "cs.CL"]
exclude_categories = ["q-bio.NC"]
recency_window_months = 6
prefer_venues = ["NeurIPS", "ICML", "ICLR-Workshop"]

[methodology]
success_criteria_override = "<prose>"
required_ablations = ["param-matched-flat", "compute-matched-rank-1"]
allow_negative_result = true

[risk]
sanity_check_above_dollars = 10
session_max_dollars = 80
require_smoke_before_real_run = true

[output]
register = "formal-paper" | "lab-notebook" | "teaching" | "code-comment"
default_target = "ICML 2026 MI Workshop submission"

[workflow]
scope_lock = true
require_clean_before_commit = true
require_audit_subagent_before_train = true
prefer_opus_for = ["attack", "novelty-check"]
prefer_sonnet_for = ["fix-list", "research-collation"]

[dismissals]
active_categories = ["ml-architectural"]   # which DISMISSALS.md tags
                                            # are load-bearing this mode

[deadline]
target_date = "YYYY-MM-DD"
scope_lock = true
```

### Override semantics

When agent code or a hook needs a value (e.g., the GPU spend ceiling):

1. Active mode has the field → use it.
2. Otherwise, central corpus has the field (e.g.,
   `INDEX.md` `risk_threshold`) → use it.
3. Otherwise, fall back to harness default.

This is layered look-up, not merge-and-rewrite. The on-disk corpus is
not modified by mode switches.

### Built-in mode templates

Rockie ships these in
`project-harness/skills/mode/templates/`. The installer copies them
into `.rockie/taste/modes/` on first run if the directory doesn't
yet exist.

- `default.toml` — empty overlay; baseline.
- `paper-crunch.toml` — deadline-locked: scope_lock, formal register,
  required ablations, smoke gates, opus on review/attack.
- `exploratory.toml` — opposite: no scope lock, broader reading
  window, sonnet-first, register="lab-notebook".
- `dogfooding.toml` — for harness self-modification: small budgets,
  fast iterations, looser gates so the tester can move fast.
- `learning.toml` — register="teaching", deeper-explanation rules,
  methodology gates relaxed.

Researchers customize by copying a template and editing, or invoking
`/mode new <name>` for an interview-driven creation flow.

### `/mode` skill commands

- `/mode show` — print active mode + the overlay diff against central.
- `/mode list` — show all modes with their one-line descriptions.
- `/mode switch <name>` — atomic write to `_active`.
- `/mode new <name> [--from <template>]` — copy from template (or
  blank), open in editor.
- `/mode edit <name>` — open existing mode in editor.
- `/mode diff <a> <b>` — compare two modes.

### Conflict detection at SessionStart

When mode is loaded, surface obvious mismatches:
- mode requires `hardware.preferred_provider = "runpod"` but
  `RUNPOD_API_KEY` is unset → WARN.
- mode says `spot_only = true` but `ROCKIE_GPU_MODE = none` →
  WARN.
- mode references `dismissals.active_categories = ["X"]` and no
  DISMISSALS.md entry has tag `[X]` → WARN.

Warnings are advisory, not blocking. The agent surfaces them with
the rest of the SessionStart report.

### Discarded: per-area profiles

We considered separate per-area corpora (
`.rockie/taste/{ml-research,neuro}/...`), then rejected:
- A researcher's identity (SOUL.md, STYLE.md) doesn't fork by
  research area; only operational policy does.
- Forces redundant onboarding interviews per area.
- Loses cross-area learning signal in the [LEARN] DB.
- Modes are smaller, easier to swap mid-session.

Modes are the smaller, more composable abstraction.

## Dogfood plan

Test the prompt by having a fresh agent (the interviewer) interview
another fresh agent that's been briefed on the
`learned-representations` repo (the simulated researcher). The
interviewer compiles a TASTE.md corpus from the conversation. Real Sam
then reads the corpus and rates per file: *captures real signal /
generic platitudes / wrong*. Iterate the prompt until ≥ 4/6 files rate
"captures real signal" without hand-holding.

This dogfood is the gate on shipping. If the prompt produces
platitudes from a repo this rich, it produces platitudes from real
researchers, and the feature is decorative.
