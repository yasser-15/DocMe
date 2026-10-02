-- 0006_app_access.sql — let the Flutter app connect as a client.
--
-- WHY THIS FILE EXISTS
-- --------------------
-- `docker/compose.yaml` runs plain Postgres. There is no Kong, no PostgREST and
-- no GoTrue, so `supabase_flutter` cannot reach this database: it expects an
-- HTTP API at SUPABASE_URL, and SUPABASE_URL points at the Postgres port.
--
-- The decision (2026-10-02) is to talk to Postgres directly from Dart and let
-- Postgres keep doing what it was already proven to do. The security boundary
-- here is the ROLE, not the transport: a query run as `docme_authenticated`
-- obeys every policy in 0003_rls.sql no matter which client sent it, and a
-- query run as the owner bypasses all of them no matter how careful the client
-- was. That is the same reasoning that made the role split in 0004 necessary.
--
-- So the app:
--   1. connects as `docme_client` (below) — a LOGIN role that is NOT a superuser
--      and does NOT have BYPASSRLS,
--   2. opens a transaction,
--   3. `set local role docme_authenticated`,
--   4. `set_config('request.jwt.claims', '{"sub":"<uuid>"}', true)` so
--      auth.uid() resolves to the caller, exactly as PostgREST would.
--
-- Step 4 is why NO RLS policy needs rewriting. 0001 already defined auth.uid()
-- to read that GUC, and rls_test.sql already exercises the same two statements.
-- When GoTrue/PostgREST are added later this becomes a JWT instead of a
-- set_config call and the policies are untouched.
--
-- ---------------------------------------------------------------------------
-- Why `docme_client` must not be able to log in as `docme_authenticated`
-- directly, and why signup/authenticate are functions
-- ---------------------------------------------------------------------------
-- Before authentication the app does not yet know which user it is, so it cannot
-- present `request.jwt.claims`. Two operations therefore have to happen with no
-- identity at all: "does this email/password match?" and "create this account".
--
-- The naive fix is to GRANT SELECT on auth.users so the app can look itself up
-- by email. That is exactly the hole 0005_lock_down.sql closed (HOLE 1): the
-- table would read as every account's email and phone. Giving docme_client
-- blanket read on auth.users to make login convenient would reintroduce it.
--
-- So neither operation is a table read. They are SECURITY DEFINER functions:
-- the lookup happens inside Postgres under the owner, and the function returns
-- only what the caller is entitled to — a uuid, or NULL. docme_client ends up
-- with no table privileges on auth.users at all, only EXECUTE on two functions.
--
-- Password handling: the client derives a PBKDF2-SHA256 hash and sends that, not
-- the password, so a leaked dump of auth.users does not disclose credentials and
-- no credential ever crosses the wire. The comparison is a plain equality test
-- inside the function, which is why no pgcrypto dependency is needed.
--
-- CONSTRAINT on migration authors: this whole file runs inside one transaction
-- (see docker/migrate.sh), so nothing here may use CREATE INDEX CONCURRENTLY or
-- COMMIT.

-- ---------------------------------------------------------------------------
-- 1. Credential storage
-- ---------------------------------------------------------------------------
-- GoTrue owns this column in production. Adding it here rather than creating a
-- separate DocMe table is what keeps the eventual swap free: when GoTrue arrives
-- it populates encrypted_password on this same table and this column is dropped.
alter table auth.users
  add column if not exists password_hash text;

comment on column auth.users.password_hash is
  'PBKDF2-SHA256, format: pbkdf2_sha256$<iterations>$<base64 salt>$<base64 hash>. '
  'Local stand-in for GoTrue''s encrypted_password; dropped when GoTrue is added.';

-- ---------------------------------------------------------------------------
-- 2. The client login role
-- ---------------------------------------------------------------------------
-- LOGIN so the Dart `postgres` package can authenticate with a password.
-- Membership in docme_authenticated is what grants SET ROLE, and therefore what
-- lets the app reach any table at all — without it every query fails with
-- "permission denied", which is the fail-loud direction.
--
-- It is deliberately NOT a superuser and NOT granted BYPASSRLS. The assertion at
-- the end of this file fails the migration if that ever changes, because a
-- client role that can bypass RLS makes all of 0003_rls.sql inert.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'docme_client') then
    create role docme_client login password null;
  end if;
end
$$;

grant docme_authenticated to docme_client;

-- The password comes from the environment (DOCME_CLIENT_PASSWORD in .env),
-- passed in by docker/migrate.sh as the psql variable :'client_password'.
-- It is never written into this file: migrations are committed, .env is not.
--
-- `:'client_password'` expands to a quoted SQL literal, and is empty when the
-- variable was not supplied — which is what keeps the migration applicable in
-- environments (CI image smoke tests) that have no client credentials.
do $$
begin
  if :'client_password' <> '' then
    execute format(
      'alter role docme_client login password %L',
      :'client_password'
    );
  end if;
end
$$;

-- docme_authenticated already has USAGE on public + auth from 0004. The app
-- role needs nothing beyond the two functions below and the SET ROLE it inherits
-- through membership. In particular it gets no SELECT on auth.users.
--
-- CONNECT is granted dynamically: the migrate container is given DATABASE_URL
-- but not POSTGRES_DB, so the name has to come from current_database() rather
-- than getenv(). CREATE/GRANT DATABASE cannot be prepared, hence EXECUTE.
do $$
begin
  execute format('grant connect on database %I to docme_client', current_database());
end
$$;

-- ---------------------------------------------------------------------------
-- 3. Signup
-- ---------------------------------------------------------------------------
-- Creates the auth row and the matching profiles row together, because a profile
-- without an identity (or the reverse) is an orphan neither side can reach.
--
-- SECURITY DEFINER + pinned search_path: this runs as the owner, which bypasses
-- the forced RLS on profiles. Without a pinned search_path a caller could shadow
-- `profiles` with their own table and redirect the insert.
create or replace function auth.signup(
  p_email         citext,
  p_password_hash text,
  p_full_name     text,
  p_country_code  char(2),
  p_role          text default 'patient'
) returns uuid
  language plpgsql security definer
  set search_path = public, auth
  as $$
declare
  v_id uuid;
begin
  if p_password_hash is null or p_password_hash = '' then
    raise exception 'AUTH_INVALID: password is required'
      using errcode = '22023';
  end if;
  if p_full_name is null or btrim(p_full_name) = '' then
    raise exception 'AUTH_INVALID: full name is required'
      using errcode = '22023';
  end if;
  if p_role not in ('patient', 'provider') then
    raise exception 'AUTH_INVALID: role must be patient or provider'
      using errcode = '22023';
  end if;

  select id into v_id from auth.users where email = p_email;
  if v_id is not null then
    raise exception 'AUTH_EMAIL_TAKEN: an account already exists for that email'
      using errcode = '23505';
  end if;

  insert into auth.users (email, password_hash, confirmed_at, raw_user_meta_data)
  values (p_email, p_password_hash, now(), jsonb_build_object('full_name', btrim(p_full_name)))
  returning id into v_id;

  -- country_code drives which CountryAdapter the app resolves at startup
  -- (PLAN.md section 6), so it is not nullable here either.
  insert into profiles (id, role, full_name, country_code)
  values (v_id, p_role, btrim(p_full_name), upper(p_country_code));

  return v_id;
end
$$;

comment on function auth.signup is
  'Creates an auth identity and its profile in one step. Returns the new uuid. '
  'Runs as the owner because a brand-new user has no row to present as identity.';

-- ---------------------------------------------------------------------------
-- 4. Authenticate
-- ---------------------------------------------------------------------------
-- Returns the matching user id, or NULL. Deliberately does not distinguish
-- "no such account" from "wrong password" in its message, so it cannot be used
-- to enumerate which emails are registered.
create or replace function auth.authenticate(
  p_email         citext,
  p_password_hash text
) returns uuid
  language sql stable security definer
  set search_path = auth
  as $$
  select id
  from auth.users
  where email = p_email
    and password_hash = p_password_hash
$$;

comment on function auth.authenticate is
  'Returns the caller''s uuid for a matching email + PBKDF2 hash, else NULL. '
  'A function rather than a SELECT grant, so the client never gains read access '
  'to every account''s email and phone.';

-- ---------------------------------------------------------------------------
-- 5. Privilege hygiene
-- ---------------------------------------------------------------------------
-- Postgres grants EXECUTE on new functions to PUBLIC by default. Without these
-- two lines any role could call signup and mint itself an account, and could
-- brute-force authenticate against every stored hash.
revoke all on function auth.signup(citext, text, text, char, text) from public;
revoke all on function auth.authenticate(citext, text) from public;

grant execute on function auth.signup(citext, text, text, char, text) to docme_client;
grant execute on function auth.authenticate(citext, text) to docme_client;

-- ---------------------------------------------------------------------------
-- 6. Defence in depth: the client role must never be able to bypass RLS.
-- ---------------------------------------------------------------------------
-- Mirrors the assertion in 0004. If someone grants BYPASSRLS or SUPERUSER to
-- docme_client — or worse, to docme_authenticated — every policy in 0003_rls.sql
-- becomes silently inert and the verification suite would pass while proving
-- nothing. Fail the migration instead.
do $$
declare
  v_bad text;
begin
  select string_agg(rolname, ', ') into v_bad
  from pg_roles
  where rolname in ('docme_client', 'docme_anon', 'docme_authenticated')
    and (rolsuper or rolbypassrls);

  if v_bad is not null then
    raise exception
      'SECURITY: role(s) % can bypass RLS. The app connects as docme_client -> docme_authenticated, and the access rules in 0003_rls.sql would be silently inert.',
      v_bad;
  end if;

  -- docme_client must not be a member of anything that owns the data either.
  -- It is a member of docme_authenticated, which owns no tables; if that ever
  -- changes, this catches it.
  if exists (
    select 1
    from pg_auth_members m
    join pg_roles member   on member.oid   = m.member
    join pg_roles granted  on granted.oid  = m.roleid
    where member.rolname = 'docme_client'
      and granted.rolname not in ('docme_authenticated')
  ) then
    raise exception
      'SECURITY: docme_client is a member of a role other than docme_authenticated. It should hold no other role memberships.';
  end if;
end
$$;