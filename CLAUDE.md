# How to work in rockie-claude

Local overlay for the official `claude` binary. Customizes the runtime in a per-tenant Fly machine when `MODE=subscription` and `BINARY=claude`.

For *what this repo does for you as a researcher*, see `README.md`. For *cross-repo orientation* (the four-harness model + alignment agent), see `../docs/architecture.md` in the workspace meta-repo.

## First reads (after the workspace `docs/` reads)

1. `README.md` — researcher-facing overview of the four jobs (taste corpus, adversarial subagents, autopilot, [LEARN] codification).
2. `project-harness/` — repo-installed harness layer.
3. `user-harness/` — user-global harness layer.
4. `claude-md/` — CLAUDE.md templates that get rendered into tenant projects.

## ⚠️ This repo is a LOCAL OVERLAY, not the canonical source

Skills, hooks, memory schema, scripts → **canonical source is `../platform-skills/`**.

The runtime image's `assemble-skills.sh` pulls from `platform-skills/` (NOT from this repo) and writes to `~/.claude/skills/` inside the per-tenant machine. This repo is a local copy used for development reference.

The Phase 6 **alignment agent** propagates changes from `platform-skills/` into this repo's mirror copies. **Don't edit skills here directly** — edit them in `platform-skills/` and let the alignment agent push.

The exceptions are intentional divergences (in `.claude/skills/align-overlays/intentional-divergences.yaml` in the meta-repo): claude-side conventions like `claude-md/` templates and slash-command invocation style (vs codex's `agents-md/` and natural-language invocation).

## Process for changes here

1. **Is this a skill/hook/memory change?** Edit `platform-skills/` instead. Don't fork here.
2. **Is this a claude-md template change?** Edit `claude-md/` here. The alignment agent will mirror to `rockie-codex/agents-md/` with translation (CLAUDE.md ↔ AGENTS.md, slash commands ↔ NL invocation).
3. **Is this a structural change to project-harness/ or user-harness/?** Likely affects rockie-codex too — flag in the PR description so the alignment agent or Sam can port.
4. **Tests:** `pnpm test` runs the smoke + lint suite (.github/workflows/smoke.yml).
5. **Commit:** Sam Larson author, no AI trailers, Conventional Commits.

## Skills you'll reach for

From the meta-repo (`../.claude/skills/`):
- `/backpressure` — required pre-commit on substantial changes.
- `/clean` — periodic AI-slop reduction.
- `/align-overlays` — when you need to verify/sync with platform-skills before a substantial change.

## Things to be aware of

- **The fork is dead; this is overlay-only.** Per the `project_subscription_auth_dead.md` decision, we don't fork the official `claude` binary. We layer skills/hooks/commands/CLAUDE.md on top via `~/.claude/`.
- **Token theft is a security concern.** OAuth credentials live on the tenant Fly volume; never leave it. See `../platform-context/SECURITY.md` §4.
- **rockie-codex parity.** When you add a new skill or change template content, the codex side may need an analog. The alignment agent flags drift; honor its PRs.

## When in doubt

- For **rockie-claude internal** decisions: `README.md` + the relevant subdir.
- For **Rockie-platform** decisions (alignment policy, four-harness model, runtime variant differences): `../docs/decisions.md` + `../docs/architecture.md` in the workspace meta-repo.
