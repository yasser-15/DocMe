-- 0001_extensions.sql — database capabilities and auth shim.

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
-- postgis  : provider/clinic/pharmacy discovery is "who is near me", which is a
--            geography + ST_DWithin query. See PLAN.md section 4.
-- pgvector : medication and specialty similarity search for the country
--            adapters. NOTE the extension is named `vector`, not `pgvector` —
--            `create extension pgvector` fails with "extension is not
--            available" even though pgvector is installed. The Docker image is
--            pgvector/pgvector; the SQL extension is vector.
-- uuid     : identifiers must be client-generatable so the mobile app can create
--            rows offline and reconcile later.
-- citext   : email uniqueness must be case-insensitive.
create extension if not exists postgis;
create extension if not exists vector;
create extension if not exists "uuid-ossp";
create extension if not exists citext;

-- ---------------------------------------------------------------------------
-- Auth shim
-- ---------------------------------------------------------------------------
-- PLAN.md models `profiles.id` as a reference to `auth.users`. We are running a
-- plain Postgres container rather than GoTrue for now, so this creates the same
-- shape GoTrue would. When GoTrue is added it takes ownership of this schema,
-- and because every table below already points at auth.users(id), the swap
-- requires no schema change at all — which is the entire point of the shim.
create schema if not exists auth;

create table if not exists auth.users (
  id                  uuid primary key default gen_random_uuid(),
  email               citext unique,
  phone               text unique,
  confirmed_at        timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  raw_user_meta_data  jsonb not null default '{}'::jsonb
);

comment on table auth.users is
  'Local stand-in for GoTrue''s auth.users. Owned by GoTrue once that service '
  'is added to the compose stack; do not insert into it directly.';

-- Supabase resolves the caller's identity through auth.uid(). We replicate the
-- same contract so every RLS policy below is written exactly as it would be in
-- production and needs no rewrite on migration.
create or replace function auth.uid() returns uuid
  language sql stable
  as $$
    select nullif(
      current_setting('request.jwt.claims', true)::jsonb ->> 'sub',
      ''
    )::uuid
  $$;

comment on function auth.uid() is
  'Identity of the caller. In local dev set it with: '
  'select set_config(''request.jwt.claims'', ''{"sub":"<uuid>"}'', false);';

-- Keeps updated_at honest without trusting the client to send it.
create or replace function public.touch_updated_at()
  returns trigger
  language plpgsql
  as $$
  begin
    new.updated_at := now();
    return new;
  end;
  $$;

-- The RLS helper functions (is_completed_appointment, has_appointment_with)
-- live in 0003_rls.sql rather than here: they reference appointments, which
-- does not exist until 0002_schema.sql has run.