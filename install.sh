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
mkdir -p "$TARGET_PROJECT/.claude"/{hooks,scripts,skills,memory,memory/migrations,.state}

rsync -a --exclude='__pycache__' "$IDASTONE/project-harness/hooks/"   "$TARGET_PROJECT/.claude/hooks/"
rsync -a --exclude='__pycache__' "$IDASTONE/project-harness/scripts/" "$TARGET_PROJECT/.claude/scripts/"
rsync -a "$IDASTONE/project-harness/memory/schema.sql" "$TARGET_PROJECT/.claude/memory/schema.sql"
rsync -a --exclude='__pycache__' "$IDASTONE/project-harness/memory/migrations/" "$TARGET_PROJECT/.claude/memory/migrations/" 2>/dev/null || true
rsync -a --exclude='__pycache__' "$IDASTONE/project-harness/skills/"  "$TARGET_PROJECT/.claude/skills/"

# Stamp a stable project_id so two checkouts of the same repo (e.g.
# ~/proj and ~/backup/proj) don't collide on directory-basename as their
# project identity. Architecture audit F12.
PROJECT_ID_FILE="$TARGET_PROJECT/.claude/project_id"
if [ ! -f "$PROJECT_ID_FILE" ]; then
  if command -v uuidgen >/dev/null 2>&1; then
    PROJECT_ID=$(uuidgen | tr 'A-Z' 'a-z')
  else
    PROJECT_ID=$(python3 -c 'import uuid;print(uuid.uuid4())')
  fi
  # Also record the basename so it's human-readable in logs.
  printf 'id=%s\nname=%s\n' "$PROJECT_ID" "$(basename "$TARGET_PROJECT")" > "$PROJECT_ID_FILE"
  echo "[+] stamped project_id=$PROJECT_ID at $PROJECT_ID_FILE"
fi

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

# ── Merge idastone .gitignore block into target project's .gitignore ────
# Idempotent: rewrites only the block between BEGIN/END idastone markers,
# leaving the user's own rules alone. Users can keep their own rules
# OUTSIDE the markers; the installer never touches those lines.
GITIGNORE_TPL="$IDASTONE/install-assets/gitignore.idastone"
GITIGNORE_DST="$TARGET_PROJECT/.gitignore"
if [ -f "$GITIGNORE_TPL" ]; then
  if [ ! -f "$GITIGNORE_DST" ]; then
    cat "$GITIGNORE_TPL" > "$GITIGNORE_DST"
    echo "[+] wrote $GITIGNORE_DST"
  elif ! grep -q '^# BEGIN idastone' "$GITIGNORE_DST"; then
    # No existing block — append.
    printf '\n' >> "$GITIGNORE_DST"
    cat "$GITIGNORE_TPL" >> "$GITIGNORE_DST"
    echo "[+] appended idastone block to $GITIGNORE_DST"
  else
    # Replace just the existing block (between markers).
    python3 - "$GITIGNORE_DST" "$GITIGNORE_TPL" <<'PY'
import pathlib, re, sys
dst = pathlib.Path(sys.argv[1]); tpl = pathlib.Path(sys.argv[2]).read_text()
text = dst.read_text()
new = re.sub(
    r'(?ms)^# BEGIN idastone\n.*?^# END idastone\n',
    tpl[tpl.index('# BEGIN idastone'):tpl.index('# END idastone')+len('# END idastone\n')],
    text, count=1,
)
dst.write_text(new)
print(f"[+] refreshed idastone block in {sys.argv[1]}")
PY
  fi
fi

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

# ── GPU provider credential wizard ───────────────────────────────────────
# Walk the user through configuring at least one GPU provider — the
# agent can't provision GPUs without one, and 2+ unlocks preemption
# survivability (router hops on OutOfStock/BidRejected).
#
# Interactive: per-provider y/N + key prompt + live curl validation.
# Non-interactive (CI): copy .env.example → .env if missing, print
# guidance, return without prompting.
credentials_wizard() {
  local target_env="$TARGET_PROJECT/.env"
  local source_template="$IDASTONE/.env.example"

  # Ensure a .env exists so users have a documented starting point.
  if [ ! -f "$target_env" ] && [ -f "$source_template" ]; then
    cp "$source_template" "$target_env"
    chmod 600 "$target_env"
    echo "[+] created $target_env from .env.example"
  fi

  if [ "$ASSUME_YES" = "1" ]; then
    echo ""
    echo "non-interactive install: skipping GPU provider setup wizard."
    echo "Add provider keys to $target_env to enable gpu.py."
    echo "See docs/providers-setup.md for signup walkthroughs."
    return 0
  fi

  echo ""
  echo "──────────────────────────────────────────────────────────────"
  echo " GPU provider setup"
  echo "──────────────────────────────────────────────────────────────"
  echo "idastone provisions GPUs through one or more providers. Configure"
  echo "at least one to use the agent's autonomous-provisioning loop."
  echo ""
  echo "  1 provider  → single-provider works, no preemption survivability"
  echo "  2 providers → router hops on preemption; recommended for runs >1hr"
  echo "  3+          → arbitrage on price + survivability across regions"
  echo ""

  local configured=0

  _wizard_setup_one() {
    # $1 display_name  $2 env_var  $3 signup_url  $4 probe-fn-name
    local name="$1" env_var="$2" url="$3" probe_fn="$4"
    if grep -E "^${env_var}=.+" "$target_env" >/dev/null 2>&1; then
      echo "  ✓ $name: already configured ($env_var present)"
      configured=$((configured+1))
      return 0
    fi
    printf "  Set up %s? [y/N] " "$name"
    read -r ans
    case "$ans" in [Yy]*) ;; *) echo "    skipped (sign up later: $url)"; return 0 ;; esac
    echo "    → get key from: $url"
    printf "    paste %s (hidden): " "$env_var"
    stty -echo 2>/dev/null
    read -r key
    stty echo 2>/dev/null
    echo ""
    if [ -z "$key" ]; then
      echo "    empty input, skipped"
      return 0
    fi
    if "$probe_fn" "$key"; then
      echo "    ✓ authenticated"
    else
      echo "    ⚠ probe didn't return 200 — saving anyway, verify at $url"
    fi
    # Idempotent upsert into .env
    if grep -E "^${env_var}=" "$target_env" >/dev/null 2>&1; then
      # macOS sed needs a backup suffix; clean it up
      sed -i.bak -E "s|^${env_var}=.*|${env_var}=${key}|" "$target_env" && rm -f "${target_env}.bak"
    else
      printf '%s=%s\n' "$env_var" "$key" >> "$target_env"
    fi
    configured=$((configured+1))
  }

  _probe_runpod() {
    curl -sf -X POST -H "Authorization: Bearer $1" \
         -H 'Content-Type: application/json' \
         -A 'idastone-install/0.1' \
         -d '{"query":"query{myself{id}}"}' \
         "https://api.runpod.io/graphql" >/dev/null 2>&1
  }
  _probe_vast() {
    curl -sf -H "Authorization: Bearer $1" \
         "https://console.vast.ai/api/v0/users/current/" >/dev/null 2>&1
  }
  _probe_prime() {
    curl -sf -H "Authorization: Bearer $1" \
         "https://api.primeintellect.ai/api/v1/pods/?limit=1" >/dev/null 2>&1
  }
  _probe_shadeform() {
    curl -sf -H "X-API-KEY: $1" \
         "https://api.shadeform.ai/v1/instances" >/dev/null 2>&1
  }

  _wizard_setup_one "RunPod"           "RUNPOD_API_KEY"     "https://www.runpod.io/console/user/settings"     _probe_runpod
  _wizard_setup_one "Vast.ai"          "VAST_API_KEY"       "https://cloud.vast.ai/account/"                   _probe_vast
  _wizard_setup_one "Prime Intellect"  "PRIME_API_KEY"      "https://app.primeintellect.ai/dashboard/tokens"   _probe_prime
  _wizard_setup_one "Shadeform"        "SHADEFORM_API_KEY"  "https://platform.shadeform.ai/settings/api"       _probe_shadeform

  echo ""
  case "$configured" in
    0)
      echo "⚠ no providers configured."
      echo "  The agent can't provision GPUs until you add at least one key to:"
      echo "    $target_env"
      echo "  See docs/providers-setup.md for full walkthroughs."
      ;;
    1)
      echo "✓ 1 provider configured."
      echo "  Single-provider operation works. No preemption survivability —"
      echo "  consider adding a second provider before long autonomous runs."
      ;;
    *)
      echo "✓ $configured providers configured. Preemption survivability enabled."
      echo "  Run \`gpu.py auth\` to verify, \`gpu.py dashboard\` to see spend."
      ;;
  esac
}

credentials_wizard

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
