-- 0003_rls.sql — Row Level Security. See PLAN.md section 5.
--
-- RLS IS THE SECURITY BOUNDARY, not app-layer checks. Everything below is
-- enforced by Postgres for every client, every edge function, and every admin
-- query that forgets to filter. An app bug cannot leak data past these
-- policies; a missing policy leaks data silently, so every table in 0002 must
-- appear here.

-- ===========================================================================
-- Policy helpers
--
-- Defined here rather than in 0001 because they read `appointments`, which is
-- created by 0002_schema.sql.
--
-- SECURITY DEFINER is essential: these are called from RLS policies, and
-- without it Postgres would re-apply the appointments policies to the lookup,
-- so a provider could not see the row that grants them access — an infinite
-- recursion of permissions. search_path is pinned so a caller cannot shadow
-- `appointments` with their own table.
-- ===========================================================================

create or replace function public.is_completed_appointment(
  p_patient_id uuid,
  p_provider_id uuid
) returns boolean
  language sql stable security definer
  set search_path = public
  as $$
    select exists (
      select 1
      from appointments a
      where a.patient_id  = p_patient_id
        and a.provider_id = p_provider_id
        and a.status      = 'completed'
    )
  $$;

comment on function public.is_completed_appointment is
  'THE critical access check. A provider may read a patient''s health_records '
  'only if a completed appointment exists between them.';

create or replace function public.has_appointment_with(
  p_patient_id uuid,
  p_provider_id uuid
) returns boolean
  language sql stable security definer
  set search_path = public
  as $$
    select exists (
      select 1
      from appointments a
      where a.patient_id  = p_patient_id
        and a.provider_id = p_provider_id
        and a.status <> 'cancelled'
    )
  $$;

comment on function public.has_appointment_with is
  'Weaker than is_completed_appointment: any non-cancelled appointment. Used when '
  'a provider writes a visit_record, which happens AT the visit and would be '
  'circular if it required the appointment to already be completed.';

-- ===========================================================================
-- Enable RLS everywhere. FORCE makes the policy apply to the table owner too,
-- which closes the most common mistake: a migration or seed script that runs
-- as the owner bypassing RLS entirely.
-- ===========================================================================

alter table profiles               enable row level security;
alter table profiles               force  row level security;

alter table provider_profiles      enable row level security;
alter table provider_profiles      force  row level security;

alter table specialties            enable row level security;
alter table specialties            force  row level security;

alter table services               enable row level security;
alter table services               force  row level security;

alter table service_areas          enable row level security;
alter table service_areas          force  row level security;

alter table availability_slots     enable row level security;
alter table availability_slots     force  row level security;

alter table appointments           enable row level security;
alter table appointments           force  row level security;

alter table visit_records          enable row level security;
alter table visit_records          force  row level security;

alter table health_records         enable row level security;
alter table health_records         force  row level security;

alter table medications            enable row level security;
alter table medications            force  row level security;

alter table prescriptions          enable row level security;
alter table prescriptions          force  row level security;

alter table medication_schedule    enable row level security;
alter table medication_schedule    force  row level security;

alter table medication_logs        enable row level security;
alter table medication_logs        force  row level security;

alter table pharmacies             enable row level security;
alter table pharmacies             force  row level security;

alter table med_orders             enable row level security;
alter table med_orders             force  row level security;

alter table insurance_plans        enable row level security;
alter table insurance_plans        force  row level security;

alter table provider_insurance     enable row level security;
alter table provider_insurance     force  row level security;

alter table patient_subscriptions  enable row level security;
alter table patient_subscriptions  force  row level security;

alter table ratings                 enable row level security;
alter table ratings                 force  row level security;

-- ===========================================================================
-- Public reference data — no PHI, readable by anyone including anonymous.
-- ===========================================================================

create policy specialties_read on specialties
  for select using (true);

create policy medications_read on medications
  for select using (true);

create policy pharmacies_read on pharmacies
  for select using (true);

create policy insurance_plans_read on insurance_plans
  for select using (true);

-- ===========================================================================
-- profiles — own row only.
-- ===========================================================================

create policy profiles_select_own on profiles
  for select using (id = auth.uid());

create policy profiles_insert_own on profiles
  for insert with check (id = auth.uid());

create policy profiles_update_own on profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

-- No delete policy: account deletion is a deliberate account-lifecycle
-- operation, not something a client may do to its own row.

-- ===========================================================================
-- provider_profiles — readable by all, writable only by the provider.
-- ===========================================================================

create policy provider_profiles_read on provider_profiles
  for select using (true);

create policy provider_profiles_insert_own on provider_profiles
  for insert with check (id = auth.uid());

create policy provider_profiles_update_own on provider_profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

create policy provider_profiles_delete_own on provider_profiles
  for delete using (id = auth.uid());

-- ===========================================================================
-- services / service_areas — patients see published only; providers manage own.
-- ===========================================================================

create policy services_read on services
  for select using (is_published or provider_id = auth.uid());

create policy services_insert_own on services
  for insert with check (provider_id = auth.uid());

create policy services_update_own on services
  for update using (provider_id = auth.uid()) with check (provider_id = auth.uid());

create policy services_delete_own on services
  for delete using (provider_id = auth.uid());

create policy service_areas_read on service_areas
  for select using (true);

create policy service_areas_all_own on service_areas
  for all using (provider_id = auth.uid()) with check (provider_id = auth.uid());

-- ===========================================================================
-- availability_slots — open slots are public; a provider manages their own.
-- ===========================================================================

create policy availability_slots_read on availability_slots
  for select using (status = 'open' or provider_id = auth.uid());

create policy availability_slots_own on availability_slots
  for all using (provider_id = auth.uid()) with check (provider_id = auth.uid());

-- ===========================================================================
-- appointments — both sides see only their own appointments.
-- ===========================================================================

create policy appointments_select_own on appointments
  for select using (patient_id = auth.uid() or provider_id = auth.uid());

create policy appointments_insert_patient on appointments
  for insert with check (patient_id = auth.uid());

create policy appointments_update_own on appointments
  for update using (patient_id = auth.uid() or provider_id = auth.uid())
  with check (patient_id = auth.uid() or provider_id = auth.uid());

create policy appointments_delete_own on appointments
  for delete using (patient_id = auth.uid() or provider_id = auth.uid());

-- ===========================================================================
-- visit_records — patient reads own; provider writes for their own patients.
-- ===========================================================================

create policy visit_records_select_own on visit_records
  for select using (patient_id = auth.uid() or provider_id = auth.uid());

create policy visit_records_write_provider on visit_records
  for insert with check (
    provider_id = auth.uid()
    -- NOT is_completed_appointment: notes are written AT the visit, so
    -- requiring a completed appointment would be circular.
    and public.has_appointment_with(patient_id, provider_id)
  );

create policy visit_records_update_provider on visit_records
  for update using (provider_id = auth.uid()) with check (provider_id = auth.uid());

create policy visit_records_delete_provider on visit_records
  for delete using (provider_id = auth.uid());

-- ===========================================================================
-- health_records — PHI. THE CRITICAL POLICY.
--
-- A provider gets READ ONLY, and only for patients with a COMPLETED appointment
-- with them. There is deliberately no insert/update/delete policy for the
-- provider role: clinical entries are made through visit_records, never by
-- writing the patient's own vault directly.
-- ===========================================================================

create policy health_records_patient_all on health_records
  for all using (patient_id = auth.uid()) with check (patient_id = auth.uid());

create policy health_records_provider_read on health_records
  for select using (
    public.is_completed_appointment(patient_id, auth.uid())
  );

-- ===========================================================================
-- prescriptions — patient reads own; provider writes for their own patients.
-- ===========================================================================

create policy prescriptions_select_own on prescriptions
  for select using (patient_id = auth.uid() or provider_id = auth.uid());

create policy prescriptions_insert_provider on prescriptions
  for insert with check (
    provider_id = auth.uid()
    and public.is_completed_appointment(patient_id, provider_id)
  );

create policy prescriptions_update_provider on prescriptions
  for update using (provider_id = auth.uid()) with check (provider_id = auth.uid());

-- ===========================================================================
-- medication_schedule / medication_logs — patient owns; provider reads.
-- ===========================================================================

create policy medication_schedule_patient_all on medication_schedule
  for all using (patient_id = auth.uid()) with check (patient_id = auth.uid());

create policy medication_schedule_provider_read on medication_schedule
  for select using (public.is_completed_appointment(patient_id, auth.uid()));

create policy medication_logs_patient_all on medication_logs
  for all using (patient_id = auth.uid()) with check (patient_id = auth.uid());

create policy medication_logs_provider_read on medication_logs
  for select using (public.is_completed_appointment(patient_id, auth.uid()));

-- ===========================================================================
-- med_orders — patient creates and reads own; provider reads their patients'.
-- ===========================================================================

create policy med_orders_select_own on med_orders
  for select using (patient_id = auth.uid() or public.is_completed_appointment(patient_id, auth.uid()));

create policy med_orders_insert_patient on med_orders
  for insert with check (patient_id = auth.uid());

create policy med_orders_update_patient on med_orders
  for update using (patient_id = auth.uid()) with check (patient_id = auth.uid());

-- ===========================================================================
-- provider_insurance — public read (it answers "is this doctor covered"),
-- provider writes own.
-- ===========================================================================

create policy provider_insurance_read on provider_insurance
  for select using (true);

create policy provider_insurance_own on provider_insurance
  for all using (provider_id = auth.uid()) with check (provider_id = auth.uid());

-- ===========================================================================
-- patient_subscriptions — patient owns; provider reads their patients'.
-- ===========================================================================

create policy patient_subscriptions_patient_all on patient_subscriptions
  for all using (patient_id = auth.uid()) with check (patient_id = auth.uid());

create policy patient_subscriptions_provider_read on patient_subscriptions
  for select using (public.is_completed_appointment(patient_id, auth.uid()));

-- ===========================================================================
-- ratings — public read; insert only by the patient, and only after a COMPLETED
-- appointment, so ratings cannot be brigaded or written speculatively.
-- ===========================================================================

create policy ratings_read on ratings
  for select using (true);

create policy ratings_insert_completed on ratings
  for insert with check (
    patient_id = auth.uid()
    and public.is_completed_appointment(patient_id, provider_id)
  );

create policy ratings_update_own on ratings
  for update using (patient_id = auth.uid()) with check (patient_id = auth.uid());

create policy ratings_delete_own on ratings
  for delete using (patient_id = auth.uid());