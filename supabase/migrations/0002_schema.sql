-- 0002_schema.sql — the DocMe data model. See PLAN.md section 4.
--
-- Every table that can contain PHI gets RLS in 0003_rls.sql, in the same
-- milestone. Do not add a table here and defer its policies.

-- ===========================================================================
-- Identity
-- ===========================================================================

create table profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  role          text not null check (role in ('patient', 'provider')),
  full_name     text not null,
  phone         text,
  country_code  char(2) not null,          -- ISO 3166-1; selects the country adapter
  locale        text not null default 'en',
  city          text,
  region        text,
  location      geography(point, 4326),    -- for "near me"; see PLAN.md PostGIS note
  avatar_url    text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index profiles_location_idx on profiles using gist (location);
create index profiles_role_idx    on profiles (role);
create index profiles_country_idx on profiles (country_code);

create trigger profiles_touch before update on profiles
  for each row execute function public.touch_updated_at();

create table specialties (
  id       uuid primary key default gen_random_uuid(),
  slug     text not null unique,
  name     text not null,
  icon     text,
  category text
);

create table provider_profiles (
  id                uuid primary key references auth.users(id) on delete cascade,
  specialty_id      uuid references specialties(id),
  license_no        text not null,
  clinic            text,
  bio               text,
  years_experience  int  check (years_experience >= 0),
  languages         text[] not null default '{}',
  is_verified       boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create trigger provider_profiles_touch before update on provider_profiles
  for each row execute function public.touch_updated_at();

-- ===========================================================================
-- Catalogue and coverage
-- ===========================================================================

create table services (
  id            uuid primary key default gen_random_uuid(),
  provider_id   uuid not null references auth.users(id) on delete cascade,
  specialty_id  uuid references specialties(id),
  name          text not null,
  description   text,
  price         numeric(10, 2) not null check (price >= 0),
  currency      char(3) not null,
  duration_min  int not null default 30 check (duration_min > 0),
  visit_mode    text not null check (visit_mode in ('in_person', 'video', 'home_visit')),
  is_emergency  boolean not null default false,
  is_published  boolean not null default false,
  created_at    timestamptz not null default now()
);

create index services_provider_idx on services (provider_id);

create table service_areas (
  id           uuid primary key default gen_random_uuid(),
  provider_id  uuid not null references auth.users(id) on delete cascade,
  area         geography(polygon, 4326) not null,
  label        text
);

create index service_areas_area_idx on service_areas using gist (area);

create table provider_insurance (
  provider_id        uuid not null references auth.users(id) on delete cascade,
  insurance_plan_id  uuid not null,
  primary key (provider_id, insurance_plan_id)
);

create table insurance_plans (
  id             uuid primary key default gen_random_uuid(),
  country_code   char(2) not null,
  provider_name  text not null,
  plan_name      text not null,
  tier           text,
  monthly_price  numeric(10, 2),
  currency       char(3) not null,
  coverage       jsonb not null default '{}'::jsonb
);

create table patient_subscriptions (
  id                 uuid primary key default gen_random_uuid(),
  patient_id         uuid not null references auth.users(id) on delete cascade,
  insurance_plan_id  uuid not null references insurance_plans(id),
  status             text not null check (status in ('active', 'past_due', 'cancelled', 'trial')),
  started_at         timestamptz not null default now(),
  renews_at          timestamptz
);

create index patient_subscriptions_patient_idx on patient_subscriptions (patient_id);

-- ===========================================================================
-- Booking
-- ===========================================================================

create table availability_slots (
  id                uuid primary key default gen_random_uuid(),
  provider_id       uuid not null references auth.users(id) on delete cascade,
  starts_at         timestamptz not null,
  ends_at           timestamptz not null,
  status            text not null default 'open' check (status in ('open', 'booked', 'blocked')),
  recurrence_rule   text,
  check (ends_at > starts_at)
);

create index availability_slots_provider_time_idx
  on availability_slots (provider_id, starts_at);

create table appointments (
  id            uuid primary key default gen_random_uuid(),
  patient_id    uuid not null references auth.users(id) on delete cascade,
  provider_id   uuid not null references auth.users(id) on delete cascade,
  service_id    uuid references services(id),
  slot_id       uuid references availability_slots(id),
  status        text not null default 'requested'
                  check (status in ('requested', 'confirmed', 'completed', 'cancelled', 'no_show')),
  visit_mode    text not null check (visit_mode in ('in_person', 'video', 'home_visit')),
  reason        text,
  created_at    timestamptz not null default now(),
  -- A patient cannot book themselves.
  check (patient_id <> provider_id)
);

create index appointments_patient_idx  on appointments (patient_id, created_at desc);
create index appointments_provider_idx on appointments (provider_id, created_at desc);
-- Supports the health_records policy: "patients with a completed appointment".
create index appointments_status_idx on appointments (provider_id, patient_id, status);

create table visit_records (
  id                uuid primary key default gen_random_uuid(),
  appointment_id    uuid not null unique references appointments(id) on delete cascade,
  provider_id       uuid not null references auth.users(id) on delete cascade,
  patient_id        uuid not null references auth.users(id) on delete cascade,
  chief_complaint   text,
  diagnosis         text,
  notes             text,
  follow_up_at      timestamptz,
  created_at        timestamptz not null default now()
);

create index visit_records_patient_idx  on visit_records (patient_id);
create index visit_records_provider_idx on visit_records (provider_id);

create table ratings (
  id                uuid primary key default gen_random_uuid(),
  appointment_id    uuid not null unique references appointments(id) on delete cascade,
  patient_id        uuid not null references auth.users(id) on delete cascade,
  provider_id       uuid not null references auth.users(id) on delete cascade,
  stars             int not null check (stars between 1 and 5),
  review            text,
  tags              text[] not null default '{}',
  created_at        timestamptz not null default now()
);

create index ratings_provider_idx on ratings (provider_id, created_at desc);

-- ===========================================================================
-- The vault — PHI
-- ===========================================================================

create table health_records (
  id            uuid primary key default gen_random_uuid(),
  patient_id    uuid not null references auth.users(id) on delete cascade,
  type          text not null check (type in ('condition', 'allergy', 'medication', 'labs', 'immunization')),
  title         text not null,
  code_system   text,                        -- SNOMED-CT, ICD-10, RxNorm, LOINC...
  code          text,
  notes         text,
  source        text not null default 'manual'
                  check (source in ('manual', 'healthkit', 'healthconnect', 'provider')),
  occurred_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index health_records_patient_idx on health_records (patient_id, type);

create trigger health_records_touch before update on health_records
  for each row execute function public.touch_updated_at();

-- ===========================================================================
-- Medication
-- ===========================================================================

create table medications (
  id             uuid primary key default gen_random_uuid(),
  rxcui          text,                        -- US (RxNorm)
  national_code  text,                        -- other countries
  generic_name   text not null,
  brand_name     text,
  form           text,
  strength       text,
  country_code   char(2) not null,
  embedding      vector(768),                 -- pgvector; country-adapter matching
  check (rxcui is not null or national_code is not null)
);

create index medications_embedding_idx on medications
  using hnsw (embedding vector_cosine_ops);
create index medications_country_idx on medications (country_code);
-- RxNorm and national codes are only unique within a country.
create unique index medications_rxcui_uniq
  on medications (country_code, rxcui) where rxcui is not null;
create unique index medications_national_uniq
  on medications (country_code, national_code) where national_code is not null;

create table prescriptions (
  id                 uuid primary key default gen_random_uuid(),
  visit_record_id    uuid references visit_records(id) on delete set null,
  patient_id         uuid not null references auth.users(id) on delete cascade,
  provider_id        uuid not null references auth.users(id) on delete cascade,
  medication_id      uuid not null references medications(id),
  dosage             text not null,
  frequency          text not null,
  duration_days      int check (duration_days > 0),
  instructions       text,
  refills_total      int not null default 0 check (refills_total >= 0),
  refills_used       int not null default 0 check (refills_used >= 0),
  active             boolean not null default true,
  created_at         timestamptz not null default now(),
  check (refills_used <= refills_total)
);

create index prescriptions_patient_idx  on prescriptions (patient_id);
create index prescriptions_provider_idx on prescriptions (provider_id);

create table medication_schedule (
  id                uuid primary key default gen_random_uuid(),
  prescription_id   uuid not null references prescriptions(id) on delete cascade,
  patient_id        uuid not null references auth.users(id) on delete cascade,
  times_of_day      time[] not null,          -- e.g. {08:00, 20:00}
  start_date        date not null,
  end_date          date,
  reminder_enabled  boolean not null default true,
  check (end_date is null or end_date >= start_date)
);

create index medication_schedule_patient_idx on medication_schedule (patient_id);

create table medication_logs (
  id            uuid primary key default gen_random_uuid(),
  schedule_id   uuid not null references medication_schedule(id) on delete cascade,
  patient_id    uuid not null references auth.users(id) on delete cascade,
  taken_at      timestamptz not null,
  skipped       boolean not null default false,
  note          text
);

-- One log per scheduled dose time. Enforced in the database so an offline phone
-- that retries cannot double-record a dose.
create unique index medication_logs_unique_dose
  on medication_logs (schedule_id, taken_at);
create index medication_logs_patient_idx on medication_logs (patient_id, taken_at desc);

create table pharmacies (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  location      geography(point, 4326) not null,
  address       text,
  country_code  char(2) not null,
  phone         text
);

create index pharmacies_location_idx on pharmacies using gist (location);

create table med_orders (
  id               uuid primary key default gen_random_uuid(),
  patient_id       uuid not null references auth.users(id) on delete cascade,
  pharmacy_id      uuid not null references pharmacies(id),
  prescription_id  uuid not null references prescriptions(id),
  status           text not null default 'pending'
                     check (status in ('pending', 'preparing', 'out_for_delivery', 'delivered', 'cancelled')),
  total            numeric(10, 2),
  currency         char(3),
  placed_at        timestamptz not null default now(),
  eta_at           timestamptz
);

create index med_orders_patient_idx on med_orders (patient_id, placed_at desc);