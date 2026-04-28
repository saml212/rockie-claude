# META — for agents constructing rockie itself

> **Read this first if you are an agent or contributor working ON rockie (the harness).**
> If you are an agent USING rockie in a research project, you want
> the user-facing docs at the repo root: `README.md`, `docs/ARCHITECTURE.md`,
> `docs/quickstart.md`, `docs/PORTS.md`. **Don't confuse the two.**

## What this directory is

This is the **meta-documentation** — the durable record of why rockie
exists, what shape it has, what's built, what's outstanding, and the
explicit lessons from its construction so far. It is committed to the
repo (not gitignored) because future agents extending rockie need it.

## What this directory is NOT

This is **not** end-user documentation. The harness's own README and
docs/ tree are user-facing. There is intentional crossover at the
"high-level goals / philosophy" level — those bullets appear in both.
Below that level, this directory talks about *building* the harness;
the user-facing tree talks about *using* it.

If you are tempted to put implementation details in user-facing docs,
or marketing copy in here — stop. Crossover is "what rockie is and
why," not "how it works internally" or "what to ship next."

## Contents

| File | Audience | When to read it |
|---|---|---|
| `README.md` (this file) | Any new contributor or harness-construction agent | First |
| `PHILOSOPHY.md` | Same | Before proposing architectural changes |
| `USER_JOURNEYS.md` | Same | Before changing hooks, skills, or session flow |
| `FEATURES.md` | Same | When you need the canonical "what's shipped" list |
| `ROADMAP.md` | Same | When picking the next thing to build |
| `DECISIONS.md` | Same | When a question feels like it should have an answer already |
| `LESSONS.md` | Same | Always — it's the durable record of user feedback + audit findings |
| `ONBOARDING_DESIGN.md` | Same | Before touching the `/onboard` skill or taste corpus |
| `PLAN.md` | Active session contributors | When you need a current snapshot of in-flight work |

## Crossover doctrine

The following lives in **both** this meta-tree and the user-facing tree:

1. **The tagline** — "An Autonomous AI research assistant that rocks."
   Lives here in `PHILOSOPHY.md` and at the top of `README.md`.
2. **The four pillars** (taste capture + iteration, adversarial-network
   bulletproofing, cheap indefinite autonomy, staying honest). Same —
   `PHILOSOPHY.md` here; mirrored in `README.md`.
3. **The four-gap differentiation pitch** (pre-run audit, semantic-loop
   detection, hypothesis calibration, failure taxonomy). Same — these
   are the OSS-positioning differentiators that map to pillars 2 and 4.
4. **The 7-step research loop** (Plan → Research → Build → Audit →
   Run → Assess → Codify). Same — `PHILOSOPHY.md` here; mirrored in
   `claude-md/CLAUDE.md.template`.
5. **The differentiator list** (FTS5 `[LEARN]` DB, waterfall,
   pre-experiment checklist, ntfy preemption recovery, living-doc
   pattern, `experiment-runs/`, `/deploy-team`, pre-commit sentinel,
   doc-guard, taste corpus, modes). Same — referenced from
   CONTRIBUTING.md as "duplicates get rejected."

## How meta-docs stay current

- When you ship a feature: update `FEATURES.md` (move from
  Outstanding → Built) **in the same commit**.
- When you change architecture: append to `DECISIONS.md`. Don't edit
  prior entries; new decisions append.
- When the user gives you a durable preference: write it to your
  Anthropic-side memory file AND to `LESSONS.md`. Both. Memory for
  future sessions; meta-doc for future contributors.
- When something is explicitly de-scoped: note it in `ROADMAP.md`
  with the reason. De-scoping is decision-bearing information.
- When you DELETE something stale: note in `DECISIONS.md` what was
  removed and why. Tombstone, not silent deletion.

## Tag convention

Files in `docs/_meta/` start with a comment block flagging their
purpose. Tools and agents can grep for `<!-- META:rockie-construction -->`
to identify meta-docs vs user docs unambiguously.

## When NOT to read this

You are running a research experiment. You are picking a queue item.
You are about to launch a training script. None of those need
`docs/_meta/` — they need `AGENTS.md` (when it lands), `STATE.md`,
`docs/ENVIRONMENT.md`, the active playbook. Wrong tree.
