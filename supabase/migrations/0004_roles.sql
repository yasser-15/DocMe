-- 0004_roles.sql — separate the migration role from the client roles.
--
-- WHY THIS FILE EXISTS (found by supabase/tests/rls_test.sql):
--   The POSTGRES_USER from docker/compose.yaml is created as a SUPERUSER by the
--   official postgres image. Superusers and roles with BYPASSRLS ignore row
--   level security entirely — even with FORCE ROW LEVEL SECURITY. So while
--   every table had `enable`d and `force`d RLS, any query run as that role saw
--   all rows and the policies were silently inert.
--
--   That is fine for migrations and fine for the owner. It is NOT fine for the
--   role the application connects as, which is the only role where the security
--   boundary is supposed to hold.
--
-- The split, mirroring Supabase's own model:
--   docme_app              owner + migrator. Bypasses RLS by design so that
--                          migrations can write seed data. NEVER connect the
--                          app with this role.
--   docme_anon             unauthenticated clients. Read-only on public data.
--   docme_authenticated    logged-in clients. RLS fully enforced.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'docme_anon') then
    create role docme_anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'docme_authenticated') then
    create role docme_authenticated nologin;
  end if;
end
$$;

-- Defence in depth: assert the properties that make RLS meaningful. If someone
-- later grants BYPASSRLS to a client role, this fails loudly at migration time
-- instead of silently disabling the security boundary.
do $$
declare
  v_bad text;
begin
  select string_agg(rolname, ', ') into v_bad
  from pg_roles
  where rolname in ('docme_anon', 'docme_authenticated')
    and (rolsuper or rolbypassrls);

  if v_bad is not null then
    raise exception 'SECURITY: client role(s) % can bypass RLS. The access rules in 0003_rls.sql would be silently inert.', v_bad;
  end if;
end
$$;

grant usage on schema public, auth to docme_anon, docme_authenticated;

-- Schema-level defaults. Row-level policy is what actually decides which rows;
-- these grants decide which tables are reachable at all. A missing grant fails
-- loudly (permission denied), whereas a missing policy fails silently.
grant select on all tables in schema public to docme_anon;

grant select, insert, update, delete on all tables in schema public
  to docme_authenticated;

-- auth.users is the identity table, never application data. Client roles may
-- read only their own row, which is what auth.uid() resolves against.
grant select on auth.users to docme_authenticated;

-- Default privileges: anything created by a future migration is immediately
-- reachable by the client roles, so adding a table cannot forget this step.
alter default privileges in schema public
  grant select on tables to docme_anon;
alter default privileges in schema public
  grant select, insert, update, delete on tables to docme_authenticated;

comment on role docme_authenticated is
  'The role the application connects as. RLS is fully enforced. Tests must SET '
  'ROLE to this, otherwise the superuser owner bypasses every policy and the '
  'tests prove nothing.';