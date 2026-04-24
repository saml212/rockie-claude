#!/usr/bin/env bash
# SessionStart hook: emit an onboarding status report via stderr so the
# agent sees it in the FIRST context turn.
#
# The agent reads this block, then — whatever the user's opening prompt —
# proposes a first action and asks for 'go' / redirect.
#
# This hook runs once per session. Output goes to stderr (Claude Code
# surfaces stderr into the agent's context alongside the user prompt).
set +e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"

# Stamp session start time for the wallclock budget counter. Stop hook
# calls `budget.py tick-wallclock` which reads this file to compute the
# elapsed seconds.
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("session_id",""))
except: print("")' 2>/dev/null)
if [ -n "$SESSION_ID" ]; then
  mkdir -p "$ROOT/.state"
  date +%s > "$ROOT/.state/session_start_$SESSION_ID"
fi
bash "$ROOT/scripts/rotate_hook_log.sh" 2>/dev/null
echo "[$(date -Iseconds)] session-report: fired" >> "$ROOT/memory/hook.log"

# If a .env is present AT THE REPO ROOT and the caller didn't already
# source it, load it into this hook's env so session_report.py can see
# RUNPOD_API_KEY etc. Does NOT persist beyond this hook invocation;
# the user still needs to source .env in their own shell to use the
# CLIs interactively.
if [ -f "$REPO/.env" ]; then
  set -a
  . "$REPO/.env" 2>/dev/null
  set +a
fi

# Emit the report via stderr so it appears in the agent's context.
# Keep it short enough to not blow past 4KB in typical shape.
python3 "$ROOT/scripts/session_report.py" >&2 2>/dev/null || {
  echo "[session-report] session_report.py failed (non-fatal)" >&2
}

exit 0
