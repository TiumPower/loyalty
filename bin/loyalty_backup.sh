#!/usr/bin/env bash
#
# Nightly backup of the Loyalty production database and uploaded files.
#
#   Runs from cron as the deploy user:
#     15 3 * * * /var/www/loyalty/shared/bin/loyalty_backup.sh >> /var/www/loyalty/shared/log/backup.log 2>&1
#
#   Keeps BACKUP_KEEP_DAYS (default 30) of daily snapshots in /var/www/loyalty/backups,
#   mode 700 — the dumps contain every shop's customer list and point balances.
#
# RESTORE:
#   dropdb  -h localhost -U loyalty loyalty_production
#   createdb -h localhost -U loyalty loyalty_production
#   pg_restore -h localhost -U loyalty -d loyalty_production --no-owner db/loyalty_YYYYmmdd.dump
#   tar xzf storage/storage_YYYYmmdd.tar.gz -C /var/www/loyalty/shared
#
# NOTE: these snapshots live on the SAME machine as the database. They protect
# against a bad migration, an accidental delete or a corrupted table — not
# against losing the server. Copying them off-box is a separate, still-missing
# step.

set -euo pipefail
# Dumps contain every shop's customer list — owner-only.
umask 077

APP_ROOT="${APP_ROOT:-/var/www/loyalty}"
BACKUP_ROOT="${BACKUP_ROOT:-$APP_ROOT/backups}"
KEEP_DAYS="${BACKUP_KEEP_DAYS:-30}"
ENV_FILE="$APP_ROOT/shared/.env"
STORAGE_DIR="$APP_ROOT/shared/storage"
STAMP="$(date +%Y%m%d_%H%M)"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fail() { log "FAILED: $*"; exit 1; }

[ -f "$ENV_FILE" ] || fail "no env file at $ENV_FILE"

# Read single keys out of .env WITHOUT sourcing it. Values there are unquoted
# and some contain spaces (MAIL_FROM_NAME), so `. .env` tries to run the second
# word as a command.
env_get() {
  sed -n "s/^$1=//p" "$ENV_FILE" | tail -n1 | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
}

DB_PASS="$(env_get LOYALTY_DATABASE_PASSWORD)"
[ -n "$DB_PASS" ] || fail "missing LOYALTY_DATABASE_PASSWORD in $ENV_FILE"
DB_NAME="$(env_get LOYALTY_DATABASE_NAME)"; DB_NAME="${DB_NAME:-loyalty_production}"
DB_USER="$(env_get LOYALTY_DATABASE_USER)"; DB_USER="${DB_USER:-loyalty}"
DB_HOST="$(env_get LOYALTY_DATABASE_HOST)"; DB_HOST="${DB_HOST:-localhost}"

mkdir -p "$BACKUP_ROOT/db" "$BACKUP_ROOT/storage"
chmod 700 "$BACKUP_ROOT"

# ---- Database ---------------------------------------------------------------
DUMP="$BACKUP_ROOT/db/loyalty_${STAMP}.dump"
log "dumping $DB_NAME -> $DUMP"
PGPASSWORD="$DB_PASS" pg_dump \
  -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" \
  --format=custom --compress=9 --file="$DUMP.part" \
  || fail "pg_dump returned $?"
mv "$DUMP.part" "$DUMP"

# A dump nobody ever read back is not a backup: make sure pg_restore can parse
# it and that it actually contains the tables we care about.
TABLES=$(PGPASSWORD="$DB_PASS" pg_restore --list "$DUMP" 2>/dev/null | grep -c 'TABLE DATA' || true)
[ "$TABLES" -gt 10 ] || fail "dump only lists $TABLES tables — refusing to call this a backup"
log "dump ok: $(du -h "$DUMP" | cut -f1), $TABLES tables"

# ---- Uploaded files ---------------------------------------------------------
if [ -d "$STORAGE_DIR" ]; then
  TAR="$BACKUP_ROOT/storage/storage_${STAMP}.tar.gz"
  log "archiving $STORAGE_DIR -> $TAR"
  tar czf "$TAR.part" -C "$APP_ROOT/shared" storage || fail "tar returned $?"
  mv "$TAR.part" "$TAR"
  log "storage ok: $(du -h "$TAR" | cut -f1)"
else
  log "no storage dir at $STORAGE_DIR — skipping files"
fi

# ---- Credentials needed to restore ------------------------------------------
install -m 600 "$ENV_FILE" "$BACKUP_ROOT/env_${STAMP}.txt"

# ---- Retention --------------------------------------------------------------
# Scoped to $BACKUP_ROOT, which is set above and verified non-empty.
[ -n "$BACKUP_ROOT" ] && [ -d "$BACKUP_ROOT" ] || fail "backup root vanished"
PRUNED=$(find "$BACKUP_ROOT" -type f \( -name '*.dump' -o -name '*.tar.gz' -o -name 'env_*.txt' \) \
           -mtime "+$KEEP_DAYS" -print -delete | wc -l)
find "$BACKUP_ROOT" -type f -name '*.part' -mmin +120 -delete 2>/dev/null || true

log "done — pruned $PRUNED file(s) older than $KEEP_DAYS days; $(du -sh "$BACKUP_ROOT" | cut -f1) total"
