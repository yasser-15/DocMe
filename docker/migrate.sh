#!/bin/sh
# Applies supabase/migrations/*.sql to $DATABASE_URL, in filename order.
#
# Idempotent: applied files are recorded in public.schema_migrations and skipped
# on subsequent runs, so this is safe to re-run on every container start.
#
# Deliberately NOT baked into the database image. Schema changes should not
# require an image rebuild, and a baked-in schema goes stale the moment someone
# edits a migration file.
#
# ---------------------------------------------------------------------------
# Each migration runs in ONE transaction that also records its own filename.
#
# The previous version ran `psql -f file` and then a second `psql` to insert the
# bookkeeping row. Those are two independent transactions, so a crash (or a full
# disk, or a killed container) between them left the schema changed but the file
# marked as unapplied. The next run would try to apply it again and fail on a
# non-idempotent statement such as `create table profiles (...)`.
#
# The previous version also took `pg_advisory_lock(...)` in its own psql call.
# That is a SESSION lock: psql exited immediately afterwards and released it, so
# two concurrent runners were never actually serialised.
#
# Now the lock is `pg_advisory_xact_lock`, taken inside the same transaction that
# applies the file, and the already-applied test runs after the lock is held.
# Two overlapping runners therefore serialise per migration rather than racing.
#
# CONSTRAINT on migration authors: because every migration is wrapped in a
# transaction, do not use `CREATE INDEX CONCURRENTLY` (or anything else that
# cannot run inside one). None of the current migrations do.
# ---------------------------------------------------------------------------

set -eu

: "${DATABASE_URL:?DATABASE_URL must be set}"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-/migrations}"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -c "
  create table if not exists public.schema_migrations (
    filename    text primary key,
    applied_at  timestamptz not null default now()
  );
"

found=0
for f in "$MIGRATIONS_DIR"/*.sql; do
  [ -e "$f" ] || continue
  found=1
  name=$(basename "$f")

  # One session, one transaction: take the lock, decide whether to apply, apply,
  # record. Generated rather than written inline so the whole sequence shares a
  # single connection, which is what makes the advisory lock mean anything.
  #
  # psql's \if needs a value from \gset, and \gset needs the SELECT to run inside
  # this same transaction, hence the ordering below.
  tmp=$(mktemp)
  {
    echo "begin;"
    echo "select pg_advisory_xact_lock(hashtext('docme_migrations'));"
    echo "select exists (select 1 from public.schema_migrations where filename = '$name') as already \gset"
    echo "\if :already"
    echo "  \\echo   skip    $name"
    echo "\else"
    echo "  \\echo   apply   $name"
    echo "  \\i $f"
    echo "  insert into public.schema_migrations (filename) values ('$name');"
    echo "\endif"
    echo "commit;"
  } > "$tmp"

  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f "$tmp"
  rm -f "$tmp"
done

if [ "$found" -eq 0 ]; then
  echo "  no migrations found in $MIGRATIONS_DIR"
fi

echo "migrations up to date"