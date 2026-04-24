#!/usr/bin/env bash
# Idempotent: creates workflow.db from schema.sql if missing, applies
# schema.sql + any pending migrations to an existing DB.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="$ROOT/memory/workflow.db"
SCHEMA="$ROOT/memory/schema.sql"
MIGRATIONS="$ROOT/memory/migrations"
# Pin to /usr/bin/sqlite3 — some distros ship a sqlite3 on PATH without
# FTS5. /usr/bin/sqlite3 on macOS has FTS5 compiled in.
SQLITE=/usr/bin/sqlite3

# Safer corruption probe: instead of "zero-sized file ⇒ delete",
# actually query sqlite_master. A valid SQLite DB in WAL mode can have
# a 0-byte main file while all data lives in .db-wal — the old check
# would wipe an active transaction's WAL. Now we only remove the DB
# if sqlite3 itself can't open + query sqlite_master.
if [ -f "$DB" ]; then
  if ! "$SQLITE" "$DB" "SELECT 1 FROM sqlite_master LIMIT 1;" >/dev/null 2>&1; then
    echo "db: unreadable $DB — removing and reinitializing" >&2
    rm -f "$DB" "$DB-wal" "$DB-shm"
  fi
fi

"$SQLITE" "$DB" < "$SCHEMA"

# Apply numbered migrations in order, tracking user_version. A migration
# file at memory/migrations/002_add_col_cost.sql applies only if the DB
# is currently at user_version < 2.
if [ -d "$MIGRATIONS" ]; then
  CUR=$("$SQLITE" "$DB" "PRAGMA user_version;")
  for f in $(ls "$MIGRATIONS"/*.sql 2>/dev/null | sort); do
    base=$(basename "$f")
    n="${base%%_*}"
    # Strip leading zeros safely (bash would read 008 as octal).
    n=$((10#$n))
    if [ "$n" -gt "$CUR" ]; then
      echo "applying migration $base (→ user_version=$n)"
      "$SQLITE" "$DB" < "$f"
      "$SQLITE" "$DB" "PRAGMA user_version = $n;"
    fi
  done
fi

echo "db initialized: $DB"
VER=$("$SQLITE" "$DB" "PRAGMA user_version;")
"$SQLITE" "$DB" "SELECT
  'schema v$VER · ' ||
  (SELECT count(*) FROM learnings)              || ' learnings, ' ||
  (SELECT count(*) FROM dead_ends)              || ' dead-ends, ' ||
  (SELECT count(*) FROM experiments)            || ' experiments, ' ||
  (SELECT count(*) FROM code_pool)              || ' pool-entries, ' ||
  (SELECT count(*) FROM hypothesis_calibration) || ' predictions, ' ||
  (SELECT count(*) FROM sessions)               || ' sessions, ' ||
  (SELECT count(*) FROM notifications)          || ' notifications';"
