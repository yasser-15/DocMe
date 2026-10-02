#!/bin/sh
# Applies supabase/migrations/*.sql to $DATABASE_URL, in filename order.
#
# Idempotent: applied files are recorded in public.schema_migrations and skipped
# on subsequent runs, so this is safe to re-run on every container start.
#
# Deliberately NOT baked into the database image. Schema changes should not
# require an image rebuild, and a baked-in schema goes stale the moment someone
# edits a migration file.

set -eu

: "${DATABASE_URL:?DATABASE_URL must be set}"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-/migrations}"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -c "
  create table if not exists public.schema_migrations (
    filename    text primary key,
    applied_at  timestamptz not null default now()
  );
"

# Serialise concurrent runners (CI matrix + a local run can overlap). Without
# this, two processes can both decide a migration is unapplied and run it twice.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -t -c "select pg_advisory_lock(hashtext('docme_migrations'));"

found=0
for f in "$MIGRATIONS_DIR"/*.sql; do
  [ -e "$f" ] || continue
  found=1
  name=$(basename "$f")

  applied=$(psql "$DATABASE_URL" -At -c \
    "select 1 from public.schema_migrations where filename = '$name'")

  if [ "$applied" = "1" ]; then
    echo "  skip    $name"
    continue
  fi

  echo "  apply   $name"
  # ON_ERROR_STOP makes psql exit on the first error, so a migration either
  # lands completely or not at all. Never wrap this in a single outer
  # transaction: several of our migrations need CREATE INDEX CONCURRENTLY and
  # other statements that cannot run inside one.
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f "$f"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -c \
    "insert into public.schema_migrations (filename) values ('$name')"
done

if [ "$found" -eq 0 ]; then
  echo "  no migrations found in $MIGRATIONS_DIR"
fi

echo "migrations up to date"