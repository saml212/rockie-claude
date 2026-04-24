# Quickstart

Five minutes, copy-paste. Assumes macOS/Linux, Claude Code already installed.

## 1. Install into your project

```bash
git clone https://github.com/saml212/idastone.git ~/idastone
cd ~/idastone
./install.sh /path/to/your/research-project
```

The installer:
- Drops hooks + skills into `<project>/.claude/`
- Installs cross-project memory pieces into `~/.claude/`
- Seeds 14 generic harness rules into a fresh `workflow.db`
- Tells you what to do next

## 2. Drop a CLAUDE.md

Generic:
```bash
cp ~/idastone/claude-md/CLAUDE.md.template /path/to/your/project/CLAUDE.md
```

ML research preset (pre-experiment checklist tuned for training runs):
```bash
cp ~/idastone/claude-md/ml-research.md /path/to/your/project/CLAUDE.md
```

Edit the `Project` section at the bottom.

## 3. Smoke-verify your install

```bash
cd /path/to/your/project
/usr/bin/sqlite3 .claude/memory/workflow.db \
  "SELECT count(*) || ' rules' FROM learnings;"
# → 14 rules
```

Open Claude Code in the project. On your first prompt you should see (via stderr in the Claude Code UI):

```
[load-relevant-rules] Prior learnings that may apply to this prompt:
  [harness] Pin sqlite3 to /usr/bin/sqlite3 ...
```

## 4. Five commands to know

```bash
# Add an experiment to the tree + queue
python3 .claude/scripts/journal.py add --stage draft \
    --hypothesis "Doubling batch size drops val loss 0.05" \
    --run-id r001
python3 .claude/scripts/calibration.py add r001 \
    "Doubling batch size drops val loss 0.05" val_loss -0.05

# After the run
python3 .claude/scripts/journal.py close 1 \
    --metric val_loss=3.42 --is-buggy 0 --analysis "clean run"
python3 .claude/scripts/calibration.py close r001 \
    "Doubling batch size drops val loss 0.05" -0.03

# See where you stand
python3 .claude/scripts/journal.py tree
python3 .claude/scripts/journal.py best
python3 .claude/scripts/calibration.py report
python3 .claude/scripts/queue.py status
```

## 5. Enable continuous operation (optional)

Only after you have:
- A working training launcher that takes a queue-item JSON on stdin
- A populated queue (run `/queue-refill` a few times)
- A `budget.toml` with session + project ceilings

```bash
cat > .claude/autopilot.conf <<EOF
LAUNCHER_CMD="bash scripts/launch_experiment.sh"
PID_FILE=".claude/.state/training_pid"
LOG_FILE=".claude/.state/training_log"
MAX_CONSECUTIVE_FAILURES=3
COOLDOWN_BASE_SECONDS=300
COOLDOWN_MAX_SECONDS=1800
EOF

nohup bash .claude/scripts/autopilot_loop.sh > .claude/memory/autopilot.log 2>&1 &
```

Stop with `bash .claude/scripts/autopilot_loop.sh --stop`.

Read the autopilot skill doc before enabling: `project-harness/skills/autopilot/SKILL.md`.

## 6. Set up ntfy (optional, recommended)

See `docs/ntfy-setup.md`. Without it, the autopilot loop can't wake you when something needs a decision — it'll idle forever.

## 7. `[LEARN]` and `[DEAD-END]`

The two blocks the agent should emit:

```
[LEARN] <category>: <one-line rule>
Mistake: <what went wrong>
Correction: <what the right approach is>
```

```
[DEAD-END] <direction-slug>: <reason it died, specific and falsifiable>
Evidence: <path to EXPERIMENT_LOG entry or paper>
```

The Stop hooks parse these automatically. Dedupe is atomic.

## That's it

- `README.md` — why / what / how
- `docs/ARCHITECTURE.md` — how the components fit together
- `docs/PORTS.md` — every port cited to source + line
- `SECURITY.md` — risk surfaces + hardening checklist
- `CHANGELOG.md` — what shipped in each release

Open an issue if something breaks. Every script has a `--help`.
