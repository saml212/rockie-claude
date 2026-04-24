# What would make idastone the most-starred autonomous-research-harness repo

## The gaps nobody in this space has closed

From a source-level review of 11 competing harnesses (AIDE, Sakana v1/v2,
AgentLab, AI-Researcher, Paper2Code, OpenHands, smolagents, STORM,
PaperQA2, Ouroboros), these four are the persistent holes:

1. **Pre-run code audit.** Every other harness reviews *after* a run
   burns compute. None reviews the implementation *before* hitting go.
   idastone already ships this (`/deploy-team audit-pre-launch` + a
   separate auditor agent). Name the behavior, put it on the README
   hero, and publish one benchmark showing pre-run audit catches a
   shape/gradient bug that AIDE+Sakana miss post-run.

2. **Semantic-loop detection.** OpenHands has the only real
   implementation (`stuck.py` — 5 loop types). Nobody else detects
   agent monologue or alternating action-observation cycles. We port it
   in Tier A; the pitch writes itself ("idastone doesn't spin").

3. **Hypothesis calibration.** Ouroboros is the only repo logging
   predicted vs. actual metric deltas. Two extra fields in the per-run
   YAML is all it takes, and it turns the `[LEARN]` DB into a running
   honesty score. No other harness measures whether the agent's priors
   are getting better.

4. **Failure taxonomy.** Not one repo cleanly separates
   `bug | bad-hyperparam | bad-hypothesis`. Everybody lumps them.
   Owning this enum — surfaced in the post-run review and indexed in
   FTS5 — is a credibility-building artifact on its own.

Ship all four and the pitch is "the autonomous research harness that
catches bugs before you burn GPU time, notices when it's stuck, tracks
whether its predictions were right, and says honestly whether the idea
was wrong or just the implementation."

## Surfaces competitors don't have

- **Installable via `uvx` / one-line curl.** Most of these repos are
  `git clone && read the paper`. A 30-second install is table stakes
  most of them don't meet.

- **Project-local + user-global split.** AIDE, Sakana, AgentLab are
  monorepos that want to own your working directory. idastone installs
  into `<your-project>/.claude/` and composes with whatever else you
  have. This is a genuine adoption unlock — pitch it hard.

- **Claude Code plugin distribution.** Sakana v2 has two independent
  contributors (PRs #83 + #93) building Claude Code skill wrappers in
  parallel. That's the direction of travel, and we're Claude-native by
  default. Publish our own marketplace entry on day one.

- **Domain-tunable CLAUDE.md templates.** Ship `ml-research`,
  `web-research`, `reverse-engineering`, `security-research` presets.
  Nobody has this. Most lock the workflow to one genre (Sakana = paper
  generation, AIDE = Kaggle, AI-Researcher = lit review).

- **Hook-based, not framework-based.** OpenHands/smolagents want you to
  adopt their runtime. Our hooks live in your `settings.json`. Reversible
  in 5 seconds. Lower commitment = higher adoption.

- **SQLite memory, not vector DB.** Every "agent memory" repo reaches for
  Chroma/Qdrant/Pinecone. FTS5 is local, zero-config, forever-free, and
  good enough. Lead with "no API keys except Claude" as a first-class
  feature.

## Docs that would win stars

- **One-page diagram** — the 7-step Plan→Research→Build→Audit→Run→Assess
  →Codify loop with hook/DB/skill pins. Every successful research-tool
  README has a single canonical diagram.
- **"Why idastone" comparison table** — one row per competing harness,
  columns are the four gaps above + "requires git clone" + license.
  Honest, specific, checkable.
- **90-second demo video** — a real research question, the waterfall
  running, the audit agent catching a shape mismatch, the `[LEARN]`
  capturing the lesson, all in real time. No other harness has this.
- **PORTS.md** (already written) as a living doc. Shows we read the
  source of every competitor and can cite line numbers. This is the
  kind of artifact that makes researchers trust a new tool.

## Credibility-building artifacts to ship alongside launch

In leverage-÷-effort order:

1. **MLE-bench submission.** AIDE is the current champion. A pre-run-audit
   variant of their approach, run as idastone, is a direct apples-to-apples
   claim. If we win or tie, that's launch-day headline material. If we lose
   honestly, that's still a credibility artifact ("we ran it, here's where
   we fell short"). Budget: 1–2 weeks.

2. **Reproduction demo: a single famous paper, start to finish, in the harness.**
   Pick something small and clean — one of the Anthropic interpretability
   papers, or a minimal-scale SAE reproduction. Ship the transcript
   (`.team-runs/<id>/` artifact). "This harness reproduced [paper] with
   zero human intervention in X hours for $Y." Budget: 1 week.

3. **"Catches a real bug" blog post.** Take the top-10 entries the
   harness has captured in real use. Each one is a concrete, technical
   bug the harness caught. Publish as case studies with links to the
   actual commits. Researchers eat this up; it's unfakeable social
   proof. Budget: 2 days.

4. **Benchmark: bug-catch rate at audit vs. post-run.** Define a set of
   intentionally broken training scripts (shape mismatch, wrong masking,
   learning rate off by 1e3, etc.) — run them through AIDE, Sakana v2,
   and idastone. Measure: "how many GPU-minutes were burned before the
   harness caught the bug?" We should win by 10×+ because pre-run audit
   catches before compute starts. Budget: 1 week to construct + run.

5. **Failure-taxonomy dataset.** As C4 (the failure-classification enum)
   accumulates labels from real runs, publish them. "1,000 real autonomous
   ML research runs, labeled by failure mode." First-of-its-kind research
   artifact; academically citable.

## One-liner for the README hero

> **idastone** — the autonomous research harness that catches bugs before
> you burn GPU time, notices when it's stuck, tracks whether its
> predictions were right, and tells you honestly whether the idea was
> wrong or just the implementation.
