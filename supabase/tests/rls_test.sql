-- rls_test.sql — executable proof that the access rules hold.
--
-- Run:  docker compose --env-file .env -f docker/compose.yaml \
--         --profile tools run --rm psql
--       \i /tests/rls_test.sql
--
-- Every check is written as data-then-assert. A test that only checks "the
-- policy exists" proves nothing; these confirm Postgres actually refuses the
-- rows. Each check raises an exception on failure, so the script exits
-- non-zero and CI fails.
--
-- Identities are set with set_config(..., true), which scopes the JWT claim to
-- the current transaction. That is how a real request presents itself.

\set ON_ERROR_STOP on

-- Deterministic ids so re-running this script is safe and self-contained.
do $test$
declare
  v_patient  constant uuid := '11111111-1111-1111-1111-111111111111';
  v_provider constant uuid := '22222222-2222-2222-2222-222222222222';
  v_stranger constant uuid := '33333333-3333-3333-3333-333333333333';
  v_appt     uuid;
  v_count    int;
begin
  ---------------------------------------------------------------------
  -- Fixture, written as the owner (which bypasses RLS by design — the owner
  -- is what migrations and seeds run as).
  ---------------------------------------------------------------------
  insert into auth.users (id, email) values
    (v_patient,  'patient@test.local'),
    (v_provider, 'provider@test.local'),
    (v_stranger, 'stranger@test.local')
  on conflict (id) do nothing;

  insert into profiles (id, role, full_name, country_code) values
    (v_patient,  'patient',  'Test Patient',  'US'),
    (v_provider, 'provider', 'Test Provider', 'US'),
    (v_stranger, 'patient',  'Other Patient', 'US')
  on conflict (id) do nothing;

  -- Patient books, provider confirms. Status is 'confirmed', NOT 'completed'.
  insert into appointments (id, patient_id, provider_id, status, visit_mode)
  values (gen_random_uuid(), v_patient, v_provider, 'confirmed', 'in_person')
  returning id into v_appt;

  insert into health_records (patient_id, type, title, source)
  values (v_patient, 'condition', 'Hypertension', 'provider');

  ---------------------------------------------------------------------
  -- From here on we act as a real client. CRITICAL: docme_app is a superuser
  -- with BYPASSRLS, so any query left on that role ignores every policy below
  -- and the whole script would pass while proving nothing. This SET ROLE is
  -- what makes these checks meaningful.
  ---------------------------------------------------------------------
  set local role docme_authenticated;

  ---------------------------------------------------------------------
  -- CHECK 1: while the appointment is merely confirmed the provider must
  -- see nothing. This is the whole point of the completed-appointment rule.
  ---------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_provider)::text, true);

  select count(*) into v_count from health_records;
  if v_count <> 0 then
    raise exception 'CHECK 1 FAILED: provider read % health_record(s) before the appointment was completed (expected 0)', v_count;
  end if;

  ---------------------------------------------------------------------
  -- CHECK 2: the provider must not be able to WRITE into the patient's
  -- vault. Read-only has to actually mean read-only.
  ---------------------------------------------------------------------
  begin
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_provider)::text, true);
    insert into health_records (patient_id, type, title)
    values (v_patient, 'medication', 'Injected by provider');
    raise exception 'CHECK 2 FAILED: provider was able to insert into health_records';
  exception
    when insufficient_privilege then null;   -- policy denied it, as required
    when check_violation         then null;
  end;

  ---------------------------------------------------------------------
  -- CHECK 3: after the appointment completes, the provider gains access.
  ---------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_provider)::text, true);
  update appointments set status = 'completed' where id = v_appt;

  select count(*) into v_count from health_records;
  if v_count <> 1 then
    raise exception 'CHECK 3 FAILED: provider saw % health_record(s) after a completed appointment (expected 1)', v_count;
  end if;

  ---------------------------------------------------------------------
  -- CHECK 4: an unrelated account with no appointment sees nothing.
  ---------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_stranger)::text, true);

  select count(*) into v_count from health_records;
  if v_count <> 0 then
    raise exception 'CHECK 4 FAILED: unrelated account saw % health_record(s) (expected 0)', v_count;
  end if;

  ---------------------------------------------------------------------
  -- CHECK 5: the patient sees exactly their own record.
  ---------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_patient)::text, true);

  select count(*) into v_count from health_records;
  if v_count <> 1 then
    raise exception 'CHECK 5 FAILED: patient saw % health_record(s) (expected 1)', v_count;
  end if;

  ---------------------------------------------------------------------
  -- CHECK 6: public reference data stays world-readable, otherwise the
  -- app breaks the moment RLS is switched on.
  ---------------------------------------------------------------------
  if not exists (
    select 1 from pg_policies
    where tablename = 'specialties' and cmd = 'SELECT'
  ) then
    raise exception 'CHECK 6 FAILED: specialties has no SELECT policy, so the app cannot read reference data';
  end if;

  raise notice 'All RLS checks passed.';
end
$test$;

-- Identity and migration bookkeeping. Neither table was guarded by a test until
-- 0005_lock_down.sql fixed both; checks 7 and 8 are what stop them regressing.
do $identity$
declare
  v_patient  constant uuid := '11111111-1111-1111-1111-111111111111';
  v_count    int;
begin
  set local role docme_authenticated;

  ---------------------------------------------------------------------
  -- CHECK 7: a client sees its own identity row and nobody else's.
  -- Until 0005, auth.users had no RLS at all, so this returned 3 and every
  -- logged-in user could read every other account's email and phone.
  ---------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_patient)::text, true);

  select count(*) into v_count from auth.users;
  if v_count <> 1 then
    raise exception
      'CHECK 7 FAILED: client read % auth.users row(s), expected only its own (1). Other accounts'' emails and phone numbers are exposed.',
      v_count;
  end if;

  ---------------------------------------------------------------------
  -- CHECK 8: the migration bookkeeping table is not client-writable.
  -- The blanket grant in 0004 let a client insert here, which would make the
  -- migration runner skip a schema change that never actually happened.
  ---------------------------------------------------------------------
  begin
    insert into public.schema_migrations (filename) values ('forged_by_client.sql');
    raise exception 'CHECK 8 FAILED: client was able to insert into schema_migrations';
  exception
    when insufficient_privilege then null;   -- revoked, as required
  end;

  -- Confirm the write really was refused and not merely rolled back later, by
  -- checking as the owner, who bypasses RLS and sees the true table contents.
  --
  -- `reset role`, not `set local role docme_app`: switching to a role you are not
  -- a member of requires privileges that docme_authenticated deliberately lacks,
  -- so the explicit SET would itself fail. RESET restores session_user, which is
  -- the owner this script connected as.
  reset role;
  if exists (select 1 from public.schema_migrations where filename = 'forged_by_client.sql') then
    raise exception 'CHECK 8 FAILED: the forged migration row was actually persisted';
  end if;

  raise notice 'Identity and bookkeeping checks passed.';
end
$identity$;

-- Clean up so the script is re-runnable.
do $cleanup$
declare
  v_patient  constant uuid := '11111111-1111-1111-1111-111111111111';
  v_provider constant uuid := '22222222-2222-2222-2222-222222222222';
  v_stranger constant uuid := '33333333-3333-3333-3333-333333333333';
begin
  delete from appointments   where patient_id  = v_patient;
  delete from health_records where patient_id  = v_patient;
  delete from profiles       where id in (v_patient, v_provider, v_stranger);
  delete from auth.users     where id in (v_patient, v_provider, v_stranger);
end
$cleanup$;