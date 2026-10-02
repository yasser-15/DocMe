-- 0005_lock_down.sql — close two holes the role split in 0004 left open.
--
-- Found while auditing 0004_roles.sql rather than by a failing test, which is
-- the problem: nothing in the suite was looking at these tables.
--
-- HOLE 1: auth.users was readable in full by every logged-in user.
--   0004 says "Client roles may read only their own row", then does:
--       grant select on auth.users to docme_authenticated;
--   There is no RLS on auth.users, so that grant means SELECT * FROM auth.users
--   returns every account's email, phone and metadata. auth.uid() only needs
--   the caller's own row, so the fix is to enable RLS and scope it.
--
-- HOLE 2: schema_migrations was readable and writable by clients.
--   It is created by docker/migrate.sh in schema public, so 0004's blanket
--   `grant select, insert, update, delete on all tables in schema public`
--   covered it. Clients could read the migration log and, worse, INSERT or
--   DELETE rows in it — which makes the migration runner believe a migration
--   has been applied when it has not, or re-apply one that has.
--
-- HOLE 3: the blanket default privileges were the unsafe direction.
--   0004 grants all CRUD on every future table in schema public to
--   docme_authenticated. If a later migration forgets `enable row level
--   security`, the table is silently readable by every logged-in user. The file's
--   own comment notes the asymmetry ("a missing grant fails loudly, whereas a
--   missing policy fails silently") and then chooses the silent-failure option.
--   So default privileges are revoked below: new tables start unreachable and a
--   migration must opt in with an explicit GRANT. Failing closed, not open.

-- ---------------------------------------------------------------------------
-- HOLE 1: own-row-only access to the identity table.
-- ---------------------------------------------------------------------------

alter table auth.users enable row level security;

drop policy if exists auth_users_select_own on auth.users;

create policy auth_users_select_own
  on auth.users
  for select
  to docme_authenticated
  using (id = auth.uid());

-- NOT forced: the owning role (GoTrue in production, docme_app locally) must
-- keep full access to manage accounts. Forcing RLS here would lock the auth
-- service out of its own table.

revoke all on auth.users from docme_anon;

-- ---------------------------------------------------------------------------
-- HOLE 2: the migration bookkeeping table is not client data.
-- ---------------------------------------------------------------------------

revoke all on public.schema_migrations from docme_anon, docme_authenticated;

alter table public.schema_migrations enable row level security;

-- ---------------------------------------------------------------------------
-- HOLE 3: future tables must opt in to client access explicitly.
-- ---------------------------------------------------------------------------

alter default privileges in schema public
  revoke select on tables from docme_anon;
alter default privileges in schema public
  revoke select, insert, update, delete on tables from docme_authenticated;

-- ---------------------------------------------------------------------------
-- Guard rail: fail loudly at migration time if anything in schema public is
-- reachable by a client role but has no RLS. This is the condition that turns a
-- forgotten `enable row level security` from a silent PHI leak into a failed
-- migration.
-- ---------------------------------------------------------------------------
do $$
declare
  v_bad text;
begin
  select string_agg(format('%I.%I', schemaname, tablename), ', ')
    into v_bad
  from pg_tables
  where schemaname = 'public'
    and not rowsecurity;

  if v_bad is not null then
    raise exception
      'SECURITY: table(s) % in schema public have row level security DISABLED. Add `alter table ... enable row level security` to the migration that creates them.',
      v_bad;
  end if;
end
$$;