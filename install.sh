#!/usr/bin/env bash
# idastone — installer.
# Copies project-harness/ into <target>/.claude/ and user-harness/ into ~/.claude/.
# Merges hook definitions into both settings.json files (never overwrites
# existing user keys).
#
# Usage:
#   install.sh [<target-project>]
#   install.sh --project-only [<target>]     # skip user-harness (CI-friendly)
#   install.sh --yes [<target>]              # don't prompt (non-interactive)
#
# Idempotent: re-running updates the harness, never touches workflow.db
# or sentinels or your existing workflow.db rows.
set -euo pipefail

PROJECT_ONLY=0
ASSUME_YES=0
TARGET_PROJECT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project-only) PROJECT_ONLY=1; shift ;;
    --yes|-y)       ASSUME_YES=1; shift ;;
    --help|-h)      sed -n '2,11p' "$0" | sed 's/^# //; s/^#//'; exit 0 ;;
    *)              TARGET_PROJECT="$1"; shift ;;
  esac
done
TARGET_PROJECT="${TARGET_PROJECT:-$PWD}"

# Non-interactive if stdin is not a TTY (piped install, CI, etc.)
if [ ! -t 0 ]; then
  ASSUME_YES=1
fi

IDASTONE="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$TARGET_PROJECT" ]; then
  echo "error: target project dir '$TARGET_PROJECT' does not exist" >&2
  exit 2
fi
TARGET_PROJECT=$(cd "$TARGET_PROJECT" && pwd -P)

# Refuse to install idastone into its own clone.
IDASTONE_PHYS=$(cd "$IDASTONE" && pwd -P)
if [ "$TARGET_PROJECT" = "$IDASTONE_PHYS" ]; then
  echo "error: refusing to install idastone into its own clone ($TARGET_PROJECT)." >&2
  echo "       pass the path to your research project as the first argument:" >&2
  echo "         ./install.sh ~/path/to/your/research-project" >&2
  exit 2
fi

echo "┌── idastone installer ──────────────────────────────────"
echo "│  project-harness  →  $TARGET_PROJECT/.claude/"
if [ "$PROJECT_ONLY" = "1" ]; then
  echo "│  user-harness     →  (skipped: --project-only)"
else
  echo "│  user-harness     →  $HOME/.claude/"
fi
echo "└────────────────────────────────────────────────────────"

# ── Preflight ───────────────────────────────────────────────────────────
command -v /usr/bin/sqlite3 >/dev/null 2>&1 || {
  echo "error: /usr/bin/sqlite3 not found. idastone pins to /usr/bin/sqlite3 so FTS5 is guaranteed." >&2
  exit 2
}
command -v python3 >/dev/null 2>&1 || { echo "error: python3 required" >&2; exit 2; }

# FTS5 capability check — try to create a virtual FTS5 table.
/usr/bin/sqlite3 ":memory:" "CREATE VIRTUAL TABLE t USING fts5(x)" >/dev/null 2>&1 || {
  echo "error: /usr/bin/sqlite3 lacks FTS5. On macOS the system sqlite3 has it by default." >&2
  exit 2
}

# ── Confirm (only if existing .claude/ and interactive) ──────────────────
if [ -d "$TARGET_PROJECT/.claude" ] && [ "$ASSUME_YES" = "0" ]; then
  printf "[?] %s/.claude already exists. Merge non-destructively? [Y/n] " "$TARGET_PROJECT"
  read -r ans
  ans=${ans:-Y}
  case "$ans" in
    [Yy]*) ;;
    *)     echo "aborted."; exit 1 ;;
  esac
fi

# ── helper: merge hook block into a settings.json using python stdlib ────
merge_settings() {
  local source_settings="$1" target_settings="$2"
  python3 - "$source_settings" "$target_settings" <<'PYEOF'
import json, sys, pathlib
src = pathlib.Path(sys.argv[1]); dst = pathlib.Path(sys.argv[2])
new_cfg = json.loads(src.read_text())
if dst.exists():
    try:
        cur = json.loads(dst.read_text())
    except json.JSONDecodeError:
        print(f"[!] {dst} is not valid JSON; refusing to merge", file=sys.stderr)
        sys.exit(1)
else:
    cur = {}

def merge_hooks(dst_hooks, src_hooks):
    # Each event (e.g. "Stop") maps to a list of {matcher?, hooks:[...]}.
    # We append idastone's items but dedupe by command string so re-install
    # stays idempotent.
    for event, blocks in src_hooks.items():
        dst_hooks.setdefault(event, [])
        existing_cmds = set()
        for b in dst_hooks[event]:
            for h in (b.get("hooks") or []):
                existing_cmds.add(h.get("command"))
        for blk in blocks:
            filtered = {"hooks": []}
            if "matcher" in blk:
                filtered["matcher"] = blk["matcher"]
            for h in blk.get("hooks", []):
                if h.get("command") not in existing_cmds:
                    filtered["hooks"].append(h)
                    existing_cmds.add(h.get("command"))
            if filtered["hooks"]:
                dst_hooks[event].append(filtered)

cur.setdefault("hooks", {})
merge_hooks(cur["hooks"], new_cfg.get("hooks", {}))
dst.write_text(json.dumps(cur, indent=2) + "\n")
print(f"[+] merged hooks into {dst}")
PYEOF
}

# ── Install project-harness ──────────────────────────────────────────────
mkdir -p "$TARGET_PROJECT/.claude"/{hooks,scripts,skills,memory,.state}

rsync -a --exclude='__pycache__' "$IDASTONE/project-harness/hooks/"   "$TARGET_PROJECT/.claude/hooks/"
rsync -a --exclude='__pycache__' "$IDASTONE/project-harness/scripts/" "$TARGET_PROJECT/.claude/scripts/"
rsync -a "$IDASTONE/project-harness/memory/schema.sql" "$TARGET_PROJECT/.claude/memory/schema.sql"
rsync -a --exclude='__pycache__' "$IDASTONE/project-harness/skills/"  "$TARGET_PROJECT/.claude/skills/"

# Merge project-harness settings (hook registrations)
merge_settings "$IDASTONE/project-harness/settings.json" "$TARGET_PROJECT/.claude/settings.json"

# Init / migrate DB
if [ ! -f "$TARGET_PROJECT/.claude/memory/workflow.db" ]; then
  bash "$TARGET_PROJECT/.claude/scripts/init_db.sh"
  (cd "$TARGET_PROJECT" && python3 .claude/scripts/seed_hard_rules.py)
  echo "[+] initialized workflow.db with generic harness rules"
else
  # Re-apply schema (idempotent — CREATE IF NOT EXISTS only). Does NOT
  # migrate column changes; for destructive schema upgrades, consult
  # CHANGELOG.md (when we have versioned releases).
  /usr/bin/sqlite3 "$TARGET_PROJECT/.claude/memory/workflow.db" < "$TARGET_PROJECT/.claude/memory/schema.sql"
  echo "[.] existing workflow.db: applied CREATE-IF-NOT-EXISTS schema additions"
fi

chmod +x "$TARGET_PROJECT/.claude/hooks/"*.sh "$TARGET_PROJECT/.claude/scripts/"*.sh 2>/dev/null || true

# ── Install user-harness ─────────────────────────────────────────────────
if [ "$PROJECT_ONLY" = "0" ]; then
  mkdir -p "$HOME/.claude"/{hooks,skills,scripts,teams}

  rsync -a "$IDASTONE/user-harness/hooks/" "$HOME/.claude/hooks/"
  rsync -a --exclude='__pycache__' "$IDASTONE/user-harness/scripts/memory/" "$HOME/.claude/scripts/memory/"
  rsync -a --exclude='__pycache__' "$IDASTONE/user-harness/skills/deploy-team/" "$HOME/.claude/skills/deploy-team/"
  rsync -a --exclude='node_modules' "$IDASTONE/user-harness/teams/" "$HOME/.claude/teams/"
  chmod +x "$HOME/.claude/hooks/"*.sh 2>/dev/null || true

  # Merge user-harness settings (SessionStart, PreCompact, UserPromptSubmit).
  # This closes the biggest gap from the audit: hooks previously shipped
  # but unregistered.
  merge_settings "$IDASTONE/user-harness/settings.json" "$HOME/.claude/settings.json"

  echo "[+] installed user-global hooks + scripts + /deploy-team + teams/"
fi

# ── CLAUDE.md nudge ──────────────────────────────────────────────────────
if [ ! -f "$TARGET_PROJECT/CLAUDE.md" ]; then
  echo ""
  echo "──────────────────────────────────────────────────────────────"
  echo "next step — drop a CLAUDE.md at the root of your project:"
  echo ""
  echo "  # generic:"
  echo "  cp $IDASTONE/claude-md/CLAUDE.md.template $TARGET_PROJECT/CLAUDE.md"
  echo ""
  echo "  # for an ML research project:"
  echo "  cp $IDASTONE/claude-md/ml-research.md     $TARGET_PROJECT/CLAUDE.md"
  echo ""
  echo "then edit the 'Project' section for your specifics."
  echo "──────────────────────────────────────────────────────────────"
fi

# ── ntfy nudge ───────────────────────────────────────────────────────────
if [ -z "${NTFY_TOPIC:-}" ]; then
  echo ""
  echo "optional: set NTFY_TOPIC in your shell profile for push notifications."
  echo "see $IDASTONE/docs/ntfy-setup.md"
fi

# ── Node orchestrator nudge ──────────────────────────────────────────────
if [ "$PROJECT_ONLY" = "0" ] && [ ! -d "$HOME/.claude/teams/orchestrator/node_modules" ]; then
  echo ""
  echo "optional: the /deploy-team Node orchestrator needs npm install:"
  echo "  cd $HOME/.claude/teams/orchestrator && npm install"
fi

echo ""
echo "✓ idastone install complete."
