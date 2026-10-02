# DocMe — Product & Engineering Plan

> Living document. Update the **Decisions Log** whenever a choice changes and why.
> Last updated: 2026-10-02

---

## 1. Product Vision

DocMe is a **total personal health platform**, not a doctor-booking app. Two applications
form a closed loop:

| App | Platform | Role |
| --- | --- | --- |
| **patient_app** | iOS + Android | Discover care, book it, own the health record, never miss a dose |
| **provider_app** | Windows + macOS desktop | See incoming appointments, manage schedule, write clinical records + prescriptions |

The loop closes when a provider writes a prescription on desktop and it appears on the
patient's phone, schedules a reminder, and accumulates adherence data. See §9.

---

## 2. Scope

### In scope (Phase 1)
- Doctor / medical service discovery filtered by **specialty category** and **city + region**
- Geolocation → reverse geocoding → local results; radius/region filtering
- Ratings + testimonials attached to services
- Emergency **home-visit** dispatch
- Personal health vault: past visits, conditions, medications used, allergies
- Centralized health sync from **Apple Health** and **Android Health Connect**
- Medication reminders (adherence) + refill reminders
- Pharmacy ordering to the user
- Insurance plan subscription + "is this provider covered?" check
- Provider desktop dashboard: incoming appointments, availability, records

### Out of scope (deferred past Phase 1)
- Payments (Stripe)
- Video consultations
- Real pharmacy / insurance carrier API integrations (interfaces + seeded adapters only)
- iOS compilation verification (blocked on this host — see §10)

---

## 3. Repository Layout

```
DocMe/
├── packages/
│   ├── docme_core/     # domain models, repositories, Supabase layer, DI, country adapters
│   ├── docme_ui/       # Liquid Glass design system, theme, shared widgets
│   └── patient_app/    # Flutter app — android/ + ios/
│   # provider_app/     # Flutter desktop — M7, after mobile is proven
├── docker/
│   ├── compose.yaml      # db service + one-shot migrate/psql/test jobs
│   ├── postgres/         # PostGIS + pgvector image
│   ├── ci/               # pinned Flutter 3.47.6 image for containerised builds
│   └── migrate.sh        # idempotent migration runner
├── supabase/
│   ├── migrations/     # schema, RLS policies, PostGIS, seeds — append-only
│   ├── tests/          # executable RLS verification
│   └── functions/      # edge functions: refill detection, push dispatch
├── build.ps1           # monorepo task runner (db, apk, check, docker)
├── .agents/skills/liquid-glass-widgets/SKILL.md
├── docs/PLAN.md
└── CLAUDE.md
```

`docme_core` and `docme_ui` are pure Dart packages consumed by both apps, so the domain
model and the glass design language cannot drift apart.

### Container isolation

The goal is that no service, app, or job can affect another. What that means concretely:

- **Services** run in their own containers. Postgres lives in a Compose-generated container
  name; nothing is installed on the host beyond Docker itself.
- **State** lives in named Docker volumes, never a host bind mount, so
  `docker compose down -v` is a complete reset and the host filesystem stays clean.
- **Parallel copies** work because there is no `container_name:` **and no explicit volume
  or network `name:`**. Both were bugs: pinning `name: docme_pgdata` makes the volume a
  global resource, so `-p docme-b` attached the second stack to the first stack's
  database. Compose derives every resource name from the project name. The project name
  and port both come from the env file, so a second copy needs its own env file
  (`-EnvFile .env.b` on the task runner).
- **Network exposure** is loopback-only. Every published port binds `127.0.0.1` because
  this database holds PHI; nothing is reachable from the LAN.
- **Ports are non-default** (`54329`, not `5432`) so we never fight a Postgres the
  developer already runs.
- **Apps** are artifacts, not services — a mobile APK cannot be "run" as a container. The
  app-side guarantee is reproducible disposable builds via `docker/ci/Dockerfile`.

### Role split (verified by `supabase/tests/rls_test.sql`)

| Role | Bypasses RLS | Used for |
| :--- | :--- | :--- |
| `docme_app` | yes — superuser + BYPASSRLS | migrations, seeds |
| `docme_anon` | no | unauthenticated reads of public data |
| `docme_authenticated` | no | the application |

This split is not theoretical. `POSTGRES_USER` is created as a superuser by the official
postgres image, and superusers ignore RLS entirely — so while every table had
`enable`d and `force`d RLS, every query run as that role saw all rows and **the policies
were silently inert**. The RLS test caught it by asserting on row counts rather than on
policy existence. Any test asserting access rules must `SET LOCAL ROLE
docme_authenticated;` first.

---

## 4. Data Model (PostgreSQL + PostGIS + RLS)

```
profiles              id→auth.users, role(patient|provider), full_name, phone,
                      country_code, locale, city, region, geography(Point,4326)

provider_profiles     id→auth.users, specialty_id, license_no, clinic, bio,
                      years_experience, languages[], is_verified

specialties           slug, name, icon, category
                      (Cardiology, Dermatology, Pediatrics, General, Dental,
                       Ophthalmology, Neurology, Orthopedics, Psychiatry, OB/GYN)

services              provider_id, specialty_id, name, description, price, currency,
                      duration_min, visit_mode(in_person|video|home_visit), is_emergency

service_areas         provider_id, geography(Polygon,4326) — coverage + home-visit range
availability_slots    provider_id, starts_at, ends_at,
                      status(open|booked|blocked), recurrence_rule
appointments          patient_id, provider_id, service_id, slot_id,
                      status(requested|confirmed|completed|cancelled|no_show),
                      visit_mode, reason, created_at
visit_records         appointment_id, provider_id, patient_id, chief_complaint,
                      diagnosis, notes, follow_up_at
health_records        patient_id, type(condition|allergy|medication|labs|immunization),
                      title, code_system, code, notes,
                      source(manual|healthkit|healthconnect|provider), occurred_at
medications           catalog: rxcui|national_code, generic_name, brand_name,
                      form, strength, country_code
prescriptions         visit_record_id, patient_id, provider_id, medication_id,
                      dosage, frequency, duration_days, instructions,
                      refills_total, refills_used, active
medication_schedule   prescription_id, patient_id, times_of_day[], start_date,
                      end_date, reminder_enabled
medication_logs       schedule_id, taken_at, skipped, note
pharmacies            name, geography(Point,4326), address, country_code, phone
med_orders            patient_id, pharmacy_id, prescription_id, status, total,
                      currency, placed_at, eta_at
insurance_plans       country_code, provider_name, plan_name, tier, monthly_price,
                      currency, coverage jsonb
provider_insurance    provider_id, insurance_plan_id   ← "is this doctor covered"
patient_subscriptions patient_id, insurance_plan_id, status, started_at, renews_at
ratings               appointment_id, patient_id, provider_id, stars(1-5), review,
                      tags[], created_at
```

### Why PostGIS
Discovery is "who is available near me, in my city/region". `geography` + `ST_DWithin`
gives that as a single indexed query. `geocoding` (Baseflow) supplies the reverse-geocode
from raw GPS into `city`/`region`, which then filters non-spatial results.

---

## 5. RLS Policy Matrix

Row Level Security is the security boundary — **not** app-layer checks. Postgres enforces
it for every client *and* every Edge Function.

| Table | Patient | Provider | Public |
| --- | --- | --- | --- |
| `profiles` | read/write own | read/write own | — |
| `provider_profiles` | read | read/write own | read (verified) |
| `specialties` | read | read | read |
| `services` | read | read/write own | read (published) |
| `availability_slots` | read open | read/write own | — |
| `appointments` | CRUD own | CRUD own `provider_id` | — |
| `visit_records` | read own | CRUD own `provider_id` | — |
| `health_records` | CRUD own | **read only, patients with a completed appointment** | — |
| `prescriptions` | read own | write for own patients | — |
| `medication_logs` | CRUD own | read own patients | — |
| `pharmacies` | read | read | read |
| `med_orders` | create/read own | read own patients | — |
| `insurance_plans` | read | read | read |
| `provider_insurance` | read | write own | read |
| `patient_subscriptions` | CRUD own | read own patients | — |
| `ratings` | insert own (requires `status='completed'`) | read own | read |

**The critical policy:** a provider may read `health_records` only for patients who have a
**completed** appointment with them. Enforced via a join, never a blanket grant. This is
the difference between a demo and something a doctor could actually use.

---

## 6. Multi-Country via Adapters

```dart
abstract class CountryAdapter {
  String get countryCode;
  DrugCatalog get drugCatalog;
  InsuranceCatalog get insurance;
  ProviderCredentialValidator get credentials;
  PharmacyNetwork get pharmacies;
}
```

- **`UsAdapter`** → [openFDA](https://open.fda.gov) `/drug/label` + `/drug/ndc`, and
  [RxNorm](https://lhncbc.nlm.nih.gov/RxNav/APIs/RxNormAPIs.html) (`getDrugs`, `rxcui`,
  `approxTerm`) for brand↔generic normalization. Both free; no API key needed at low volume.
- **`SeedCatalogAdapter`** → seeded formulary for every other market so the app is fully
  functional anywhere from day one.

Resolved from device locale/region at startup. Adding a market = one file.

---

## 7. Health Sync Capability Matrix (patient app only)

| Capability | `health` 13.3.2 | Custom Swift | Custom Kotlin |
| --- | --- | --- | --- |
| Vitals / sleep / activity | Yes | — | — |
| Weight / BP / glucose | Yes | — | — |
| **Medications** | **No** | Yes (iOS 26+) | Yes (Health Connect `MedicationRecord`) |
| **Allergies** | No | Yes (`HKClinicalTypeIdentifier.allergyRecord`) | **No — HC has no allergy type** |
| Conditions / labs / immunizations | No | Yes (`HKClinicalTypeIdentifier`) | Yes |

### Why custom platform channels
Apple only opened medication reads in **iOS 26** (WWDC25 session 321,
`HKUserAnnotatedMedication`, `HKMedicationDoseEvent`, `HKMedicationConcept`). Before
iOS 26 third-party apps **could not read medications at all**. The well-maintained `health`
plugin (13.3.2, 680 likes, carp.dk) has **zero** medication support across its entire
changelog. Health Connect *does* expose `MedicationRecord`; the plugin ignores it.

### Platform configuration
- **iOS**: HealthKit capability, `NSHealthShareUsageDescription`,
  `NSHealthUpdateUsageDescription`, deployment target ≥ 15.0. Guard medication reads with
  `if #available(iOS 26)` and degrade silently below.
- **Android**: Health Connect per-type `READ_*`/`WRITE_*` manifest permissions,
  `minSdk 26`, `MainActivity extends FlutterFragmentActivity`, privacy-policy rationale
  activity, and **`READ_HEALTH_DATA_HISTORY`** — by default Health Connect restricts reads
  to 30 days.

### Design rule
Health sync is **additive, never required**. Every source is capability-gated with a
visible "unavailable" state and a manual-entry fallback. No user is locked out for
declining, and allergies are first-class in our own DB regardless of platform support.

---

## 8. Liquid Glass Design System

Apple's rule, which we follow: **glass is the navigation layer; content stays opaque.**

```
┌─ GlassAppBar (glass, premium) ──┐
├─────────────────────────────────┤
│  Opaque content cards & lists   │
└─ GlassTabBar.minimizable ──────┘
```

Package: **`liquid_glass_widgets` ^1.8.1** (MIT, zero third-party deps, 330 likes).
Two-pass Impeller pipeline — blur pass then refraction shader — with chromatic aberration,
Fresnel rim, and a Liquid Morph teardrop engine. Renderer auto-detected per platform;
Windows/Linux/Web are statically capped at `GlassQuality.standard`.

### Required initialization
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiquidGlassWidgets.initialize();   // pre-warm shaders, zero GPU work
  runApp(LiquidGlassWidgets.wrap(
    adaptiveQuality: true,
    brightnessResolver: Theme.maybeBrightnessOf,
    theme: GlassThemeData.simple(blur: 12, thickness: 25, quality: GlassQuality.standard),
    child: const PatientApp(),
  ));
}
```

- Use **`CupertinoApp`**, not `MaterialApp` — the package is Material-free by design.
- Wrap the `Navigator` in `GlassNavigationShell` for the iOS 26 gel-morph bar transition.
- Persist the settled adaptive-quality tier to `SharedPreferences` via
  `onQualityChanged`, otherwise a ~3s warmup benchmark runs on **every** cold start.

### Quality tier budget
| Tier | Use for |
| --- | --- |
| `premium` | `GlassAppBar`, `GlassTabBar`, hero surfaces (Impeller only) |
| `standard` | Cards, inputs, interactive controls — 95% of the app |
| `minimal` | Dense scrolling lists — shader-free `BackdropFilter`, zero invocations |

### API gotchas that will bite us
Full list in `.agents/skills/liquid-glass-widgets/SKILL.md`. The dangerous ones:
- `GlassButton(onTap:)` but `GlassIconButton(onPressed:)` — **opposite conventions**
- `GlassAppBar` takes `actions: [Widget]`; there is **no** `trailing:`
- `GlassChip.label` is a `String`, not a `Widget`
- `GlassBottomBar` was **deleted** in 1.0 → use `GlassTabBar.bottom` / `.searchable`
- `GlassBarItem.tintColor` asserts unless `background: GlassBarItemBackground.separate`
- **Never** nest refractive glass inside refractive glass (double refraction + clipped springs)

---

## 9. The Loop

```
 patient_app                          Supabase                provider_app
 ───────────                          ────────                ───────────
 Browse by category + city
   └─ POST /appointments ────────────► appointments
                                        (status=requested)
                                                                     Realtime push
                                                            ◄──────────────┘
                                        slot → booked
                                        ◄────── accept / write visit_record
                                        ◄────── write prescription
                                                     └► medication_schedule
 Next dose countdown ◄── Realtime ─────────────────────────┘
 Local notification fires ──► medication_logs (adherence)
 Refill due ──► pharmacy order ◄──► med_orders
 Visit complete ──► leave rating ──► ratings + testimonials
```

---

## 10. Milestones

Mobile-first. Desktop deferred to M7.

| # | Deliverable | Exit criteria |
| --- | --- | --- |
| M0 | Flutter 3.47, licenses, monorepo, glass spike | Glass renders on Android; real frame-time baseline |
| M1 | Supabase schema, RLS, PostGIS, seeds | RLS tested against patient↔provider cross-access attempts |
| M2 | Patient: auth, home, discovery, profile, booking | Book a real appointment end-to-end in the DB |
| M3 | Prescriptions → schedule → local reminders | Prescription produces a firing phone notification |
| M4 | Health sync + permission flow | iOS 26 meds read; Android HC meds read; degrades cleanly |
| M5 | Pharmacy ordering + insurance adapters | Full flow on seeded adapters |
| M6 | Ratings loop, glass perf tuning, tests | 60fps scroll with glass; loop demoable |
| M7 | Provider desktop app | Replaces the Supabase Studio interim console |

### Interim provider console
Until M7, **Supabase Studio** acts as the provider console — set `appointments.status`,
insert `visit_records` and `prescriptions` directly. Costs zero code, and the schema +
RLS are designed for it. Replaced by the desktop app in M7.

---

## 11. Package Pins

| Package | Version | Why |
| --- | --- | --- |
| `liquid_glass_widgets` | ^1.8.1 | Liquid Glass implementation; requires Flutter ≥ 3.41 |
| `health` | 13.3.2 | HealthKit + Health Connect bridge; SDK `>=3.8.0 <4.0.0` |
| `supabase_flutter` | ^2.0.0 | Postgres/RLS/Realtime/Auth/Storage |
| `flutter_local_notifications` | 22.3.1 | zoned scheduling; DST-safe via `timezone` |
| `timezone` | latest | required for DST-correct reminders |
| `flutter_timezone` | latest | device tz detection (the `timezone` pkg can't do this) |
| `flutter_map` | ^8.3.2 | vendor-free, pure Dart, all desktop targets |
| `geocoding` | ^5.0.0 | Baseflow reverse-geocode → city/region |
| `geolocator` | latest | GPS + service areas |
| `permission_handler` | latest | runtime permission flows |

**Maps:** OSM's public tile server is **not** permitted for production use (its usage
policy bans heavy/production traffic). Tile provider must be abstracted behind an
interface with a commercial free-tier provider configured.

**Medications:** `flutter_local_notifications` requires `tz.initializeTimeZones()` at
startup plus a device-timezone lookup via `flutter_timezone`, or reminders fire
immediately or at the wrong wall-clock time. Android additionally needs
`POST_NOTIFICATIONS` (13+), `SCHEDULE_EXACT_ALARM` (12+), `RECEIVE_BOOT_COMPLETED`, and
`AndroidScheduleMode.exactAllowWhileIdle`.

---

## 12. Decisions Log

| # | Decision | Rationale |
| --- | --- | --- |
| D1 | Flutter, not React Native | Single codebase across mobile + desktop; the glass package and Impeller are Flutter-first |
| D2 | Supabase over Firebase | RLS is enforced by Postgres itself, so it holds for Edge Functions and admin paths too. PostGIS gives geo-search; Realtime gives the provider dashboard. HIPAA add-on with BAA available. |
| D3 | Two apps, shared packages | Provider is desktop (large schedule grid); patient is mobile. Shared `docme_core`/`docme_ui` prevent divergence. |
| D4 | Mobile-first, desktop at M7 | Faster feedback on the riskiest UI (glass + perf). Desktop deferred rather than dropped. |
| D5 | Custom platform channels for medications | No Flutter package exposes them. See §7. |
| D6 | Adapters for multi-country from day one | openFDA/RxNorm are US-only; seeded catalog keeps other markets functional |
| D7 | `CupertinoApp` + `GlassNavigationShell` | Package is Material-free; shell gives the iOS 26 gel-morph transition |
| D8 | Supabase Studio as interim provider console | Zero code; schema already supports it; replaced in M7 |
| D9 | Health sync additive, never blocking | Declining permissions must never lock a user out |

---

## 13. Setup Runbook

### Prerequisites
```powershell
flutter upgrade                                  # → 3.47.x REQUIRED
flutter doctor --android-licenses
flutter config --enable-windows-desktop          # only for M7
```

### Not possible on this host
- **iOS build/compile/run** — requires macOS + Xcode. The iOS target is written and
  configured but cannot be verified here. Budget a Mac or a CI runner (Codemagic /
  GitHub Actions macOS) before iOS release.
- **Windows/macOS desktop build** — needs Visual Studio 2022 with the
  **Desktop development with C++** workload
  (`Microsoft.VisualStudio.Workload.NativeDesktop`). Not installed. Deferred to M7.

### Resolved risk: `intl` caret range

`health` 13.3.2 pins `intl: ^0.20.2` (`<0.21.0`). **RESOLVED 2026-10-02** — the current
graph resolves cleanly to `intl 0.20.3`. No `dependency_overrides`, no downgrade, no
fork needed. Keep this entry as a tripwire: if `flutter pub get` ever reports a
conflict, re-check it before resorting to overrides.

### Android build configuration (verified)

`flutter build apk --debug` succeeds, but only with these non-default settings in
`packages/patient_app/android/app/build.gradle.kts`:

| Setting | Value | Why |
| :--- | :--- | :--- |
| `compileSdk` | `37` | `permission_handler_android` refuses to compile against anything lower. |
| `minSdk` | `26` | Health Connect (`:health`) declares minSdk 26; Flutter defaults to 24, which fails manifest merging. |
| `isCoreLibraryDesugaringEnabled` | `true` | Required by `flutter_local_notifications`. |
| `coreLibraryDesugaring` | `com.android.tools:desugar_jdk_libs:2.1.5` | The library the flag above pulls in. |

**Environment:** `JAVA_HOME` is not set system-wide. Gradle resolves it from
Android Studio's bundled JBR. Every shell that runs Gradle needs:

```powershell
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"   # OpenJDK 21.0.10
```

---

## 14. Verification Commands

```powershell
flutter doctor -v
flutter analyze
flutter test
flutter run -d android      # patient app
```

Nothing in this repo ships without `flutter analyze` clean and `flutter test` green.