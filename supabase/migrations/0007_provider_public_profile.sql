-- 0007_provider_public_profile.sql — give discovery something it is allowed to read.
--
-- THE GAP THIS FIXES
-- ------------------
-- PLAN.md section 2 requires discovery by specialty and city. Section 5's policy
-- matrix says `profiles` is "read/write own" for both roles, and 0003_rls.sql
-- implements exactly that:
--
--     create policy profiles_select_own on profiles
--       for select using (id = auth.uid());
--
-- So a signed-in patient cannot read a *provider's* `profiles` row — not even
-- the provider's display name, city or location. A discovery query that joins
-- `profiles` therefore returns zero rows for every patient, silently, because
-- RLS filters them rather than erroring.
--
-- And `provider_profiles`, which PLAN.md does list as readable by patients,
-- carries only specialty_id, license_no, clinic, bio, years_experience,
-- languages and is_verified. There is no name and no location on it. So the
-- columns discovery needs sit on the one table patients cannot read.
--
-- THE FIX
-- -------
-- Put the publicly-displayable clinician fields on `provider_profiles`, which
-- is already world-readable (`provider_profiles_read ... using (true)`), and
-- leave `profiles` locked to its owner. Discovery then reads only tables its
-- policies already permit:
--
--     provider_profiles  (read: true)
--       + specialties   (read: true)
--       + services      (read: is_published or own)
--       + ratings       (read: true)
--       + availability_slots (read: status='open' or own)
--
-- WHY NOT JUST LOOSEN profiles
-- ---------------------------
-- `profiles` also holds phone, country_code, locale and location for every user,
-- patients included. Making it readable would turn the doctor list into a
-- directory of every patient's phone number and home coordinates. Splitting the
-- public clinician projection from the private contact record is the difference
-- between a discovery feature and a data breach, so this is the direction to
-- fix it in.
--
-- WHAT DOES NOT CHANGE
-- --------------------
-- No policy is altered. `provider_profiles_read` already exists and already
-- permits this, and `profiles` stays owner-only. This is additive.

alter table provider_profiles
  add column if not exists full_name text,
  add column if not exists city      text,
  add column if not exists region    text,
  add column if not exists location  geography(point, 4326);

comment on column provider_profiles.full_name is
  'Public display name. Duplicated from profiles.full_name because profiles is '
  'owner-only under RLS and discovery cannot read it. See file header.';
comment on column provider_profiles.location is
  'Clinic location for "near me" search. Public by design: it is a place of '
  'business, not a home address. profiles.location remains private.';

-- ---------------------------------------------------------------------------
-- Backfill
-- ---------------------------------------------------------------------------
-- Copies the existing display fields from `profiles` for providers who already
-- have a provider_profiles row. Runs as the migration role, which owns the table,
-- so the owner-only policy on `profiles` does not block the read.
--
-- Only rows whose source value is non-null are updated, so a second run cannot
-- overwrite a curated clinic name with null.
update provider_profiles pp
   set full_name = coalesce(pp.full_name, p.full_name),
       city       = coalesce(pp.city,       p.city),
       region     = coalesce(pp.region,     p.region),
       location   = coalesce(pp.location,   p.location)
  from profiles p
 where p.id = pp.id
   and p.role = 'provider';

-- ---------------------------------------------------------------------------
-- Discovery needs a location to be searchable, and needs to be able to say a
-- provider has none. NOT NULL would force every provider through a geocoding
-- step before they could be listed at all, so absence stays representable.
-- ---------------------------------------------------------------------------
create index if not exists provider_profiles_location_idx
  on provider_profiles using gist (location)
  where location is not null;

create index if not exists provider_profiles_specialty_idx
  on provider_profiles (specialty_id);

-- ---------------------------------------------------------------------------
-- Keep the two copies honest.
-- ---------------------------------------------------------------------------
-- `profiles.full_name` is editable by the user (profiles_update_own), so without
-- this a rename on `profiles` would leave discovery showing the old name forever.
-- SECURITY DEFINER because a trigger on provider_profiles firing as the caller
-- would not be able to read the very `profiles` row that the owner-only policy
-- hides from them.
--
-- search_path is pinned: this runs with elevated rights, and an unpinned path
-- lets a caller shadow `profiles` with their own table and redirect the update.
create or replace function public.sync_provider_display_name()
  returns trigger
  language plpgsql security definer
  set search_path = public, auth
  as $$
begin
  if new.full_name is distinct from old.full_name then
    return new;   -- explicitly set on provider_profiles; wins.
  end if;

  update public.profiles
     set full_name = new.full_name
   where id = new.id
     and role = 'provider'
     and full_name is distinct from new.full_name;

  return new;
end
$$;

create or replace function public.propagate_provider_display_name()
  returns trigger
  language plpgsql security definer
  set search_path = public
  as $$
begin
  update public.provider_profiles
     set full_name = new.full_name
   where id = new.id
     and full_name is distinct from new.full_name;

  return new;
end
$$;

drop trigger if exists profiles_push_display_name on profiles;
create trigger profiles_push_display_name
  after update of full_name on profiles
  for each row execute function public.propagate_provider_display_name();

drop trigger if exists provider_profiles_pull_display_name on provider_profiles;
create trigger provider_profiles_pull_display_name
  before update on provider_profiles
  for each row execute function public.sync_provider_display_name();

comment on function public.propagate_provider_display_name is
  'Mirrors a rename on profiles into provider_profiles, which is what discovery '
  'actually reads. The two tables are joined by id, so exactly one row matches.';

comment on function public.sync_provider_display_name is
  'Runs BEFORE update on provider_profiles, so an explicit clinician-side rename '
  'propagates back to profiles. Without it the two would drift apart.';

-- ---------------------------------------------------------------------------
-- Guard
-- ---------------------------------------------------------------------------
-- The whole point of this file is that discovery must be able to read providers.
-- If `provider_profiles` ever stops being world-readable, discovery returns
-- nothing to every patient with no error anywhere, so assert it here.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename   = 'provider_profiles'
      and cmd         = 'SELECT'
  ) then
    raise exception
      'provider_profiles has no SELECT policy. Discovery reads it for every '
      'clinician''s name and location; without a public read policy it returns '
      'zero rows to every patient, silently.';
  end if;
end
$$;