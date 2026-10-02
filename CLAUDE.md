# DocMe — AI Agent Guide

Personal health platform. Flutter + Supabase. See `docs/PLAN.md` for the full
architecture, schema, RLS matrix, and decisions log.

## Repo Layout

```
packages/
  docme_core/    domain models, repositories, Supabase layer, country adapters
  docme_ui/      Liquid Glass design system, theme, shared widgets
  patient_app/   mobile app (android + ios)      ← current build target
  provider_app/  desktop app (windows + macos)   ← M7, not created yet
supabase/
  migrations/    schema, RLS, PostGIS, seeds
```

`patient_app` and `provider_app` both depend on `docme_core` + `docme_ui`.
Never put app-specific UI in `docme_ui`, or domain logic in `docme_core`.

---

## CRITICAL: Liquid Glass API rules

Before writing ANY UI code, read `.agents/skills/liquid-glass-widgets/SKILL.md`.
It is the authoritative API reference. It exists because the package has several
inverted and deleted APIs that are easy to get wrong from memory.

Highest-risk traps:

- `GlassButton` takes **`onTap`**; `GlassIconButton` takes **`onPressed`**. Opposite
  conventions — do not assume consistency.
- `GlassAppBar` takes **`actions: [Widget]`**. There is **no `trailing:`** parameter.
- `GlassChip.label` is a **`String`**, not a `Widget`.
- `GlassBottomBar` was **deleted** in 1.0. Use `GlassTabBar.bottom` / `.searchable`.
- `GlassBarItem.tintColor` asserts unless you also pass
  `background: GlassBarItemBackground.separate`.
- **`GlassNavigationShell` takes only `child`, `enabled`, `effectTransition`.** The
  `swipeCommitTransition` / `verticalBarBehavior` params in upstream READMEs do **not**
  exist in 1.8.1 and will not compile.
- **Never** nest refractive glass inside refractive glass (no `GlassButton`,
  `GlassSlider`, `GlassSwitch` inside `GlassCard`/`GlassGroupedSection`).
- `cupertino_icons` 2.x is a stub — icon names live in the Flutter SDK at
  `packages/flutter/lib/src/cupertino/icons.dart`. Grep that file rather than
  guessing: there is no `pill_fill` (use `capsule_fill`) and no `rectangle_portrait`
  (use `person_crop_circle`).

## Design rules

1. **Glass is the navigation layer, content stays opaque.** `GlassAppBar`,
   `GlassTabBar`, FABs, sheets, dialogs → glass. List cells, cards, article bodies,
   media → opaque. This mirrors Apple's own iOS 26 rule.
2. Use `CupertinoApp`, **not** `MaterialApp`. The package is Material-free.
   Wrap the `Navigator` in `GlassNavigationShell` for the gel-morph transition.
3. `await LiquidGlassWidgets.initialize()` before `runApp()` or you get a white
   first-frame flash.
4. Use `GlassScaffold`, not `Scaffold`, on any screen with glass bars. It handles
   z-ordering, edge fade, safe areas, and status-bar styling.
5. Quality budget — do not use `premium` liberally:
   - `premium` → app bars, tab bars, hero surfaces only
   - `standard` → default for cards/inputs/controls
   - `minimal` → dense scrolling lists (shader-free, zero GPU cost)

---

## Toolchain

- Flutter **3.47.6** stable, Dart **3.13.5**. Do not downgrade — `liquid_glass_widgets`
  requires Flutter ≥ 3.41.
- iOS **cannot be compiled on this host** (no macOS/Xcode). Write and configure the
  iOS target; verify Android only.
- Windows/macOS desktop unavailable (Visual Studio C++ workload not installed). M7.
- `JAVA_HOME` is **not** set system-wide. Before any Gradle command:
  `$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"` (OpenJDK 21.0.10).
- Android build config is intentionally non-default: `compileSdk 37` (permission_handler),
  `minSdk 26` (Health Connect), core library desugaring on (local notifications).
  Do not "restore" the Flutter defaults — the build will fail.

## Backend

Supabase. **RLS is the security boundary, not app-layer checks.** If you add a table
containing PHI, it gets RLS in the same migration — no exceptions. A provider may read
`health_records` only for patients with a *completed* appointment with them.

### Roles — do not connect as the owner

`docme_app` is a **superuser with BYPASSRLS**. It exists to run migrations and seeds and
sees every row. The application must connect as `docme_authenticated` (or `docme_anon` for
public data), where RLS is fully enforced.

Any test that asserts access rules **must** `SET LOCAL ROLE docme_authenticated;`
first. Running it as the owner silently bypasses every policy and the suite passes while
proving nothing — this exact mistake happened once already and was caught only because
the test wrote real data and asserted on row counts.

A new table needs **three** things in its migration, not one:

1. `alter table <t> enable row level security;` (plus `force` for app tables)
2. the policies
3. an explicit `grant` to `docme_authenticated` / `docme_anon`

Step 3 is easy to forget because `0004_roles.sql` used to grant CRUD on every future
table by default. That was the unsafe direction: a table that got RLS but no policy, or
no `enable`, would be silently readable by every logged-in user. `0005_lock_down.sql`
revokes those defaults and adds a guard that **raises at migration time** if any table
in `schema public` has RLS disabled. So forgetting a grant now fails loudly with
"permission denied", which is the failure mode you want. If you see that error, add the
grant; do not restore blanket default privileges.

Two tables are never client data and are revoked from both client roles:
`schema_migrations` (client-writable here meant a client could fake a migration as
applied) and `auth.users` (own-row-only via `auth_users_select_own`).

## Containers

Postgres runs in Docker; nothing is installed on the host.

```powershell
.\build.ps1 db up        # start + wait for healthy + migrate
.\build.ps1 db test      # RLS verification suite
.\build.ps1 db psql      # interactive psql
.\build.ps1 db reset     # DESTRUCTIVE: drop volume, re-migrate, re-test
.\build.ps1 docker       # build the containerised APK image
```

First run needs an env file:

```powershell
copy .env.example .env
```

Layout:

| Path | Purpose |
| :--- | :--- |
| `docker/compose.yaml` | `db` service plus one-shot `migrate`/`psql`/`test` jobs |
| `docker/postgres/Dockerfile` | PostGIS + pgvector image. No schema, no app code. |
| `docker/migrate.sh` | Applies `supabase/migrations/*.sql`, tracked in `schema_migrations` |
| `docker/ci/Dockerfile` | Pinned Flutter 3.47.6 + Android SDK for container builds |
| `supabase/migrations/` | Append-only schema + RLS, applied in filename order |
| `supabase/tests/rls_test.sql` | Executable proof the access rules hold |

Isolation guarantees: named volumes only (never a host bind mount, so `down -v` is a
clean reset), and every published port bound to `127.0.0.1` because this database
holds PHI.

Nothing declares `container_name:` **or** an explicit volume/network `name:`. Both were
a real bug: a pinned `name: docme_pgdata` is a global resource, so a second stack
started with `-p docme-b` would attach to the *first* stack's database, and `down -v`
on either would destroy the other's data. Compose derives both from the project name.

A second copy needs its own env file, because the project name *and* the published
port both come from there:

```powershell
copy .env .env.b     # then set COMPOSE_PROJECT_NAME=docme-b and POSTGRES_PORT=54330
.\build.ps1 db up -EnvFile .env.b
```

Migrations are **append-only**. `schema_migrations` records applied filenames, so editing
an already-applied file does nothing on re-run. If you change one, reset the volume.

`docker/migrate.sh` runs each migration in a **single transaction** that also writes its
own `schema_migrations` row, taking `pg_advisory_xact_lock` first. Two consequences you
must respect when writing migrations:

- Never use `CREATE INDEX CONCURRENTLY` or anything else that cannot run in a transaction.
- Never wrap a migration in your own `BEGIN`/`COMMIT`.

The earlier runner used a session-level `pg_advisory_lock` in a `psql` call that exited
immediately, so the lock was released before it did anything, and the file and its
bookkeeping row were separate transactions.

## Verification (required before considering anything done)

Use the root task runner. This is a monorepo with three pubspecs, so `flutter`
must be invoked from inside a package directory, and Gradle needs `JAVA_HOME` set:

```powershell
.\build.ps1 check                # analyze + test all three packages
.\build.ps1 check -Package docme_ui
.\build.ps1 apk                  # release APK
.\build.ps1 apk --debug          # debug APK
.\build.ps1 run                  # launch on connected device
.\build.ps1 clean -Package patient_app
```

Equivalent by hand, from the package you changed:

```powershell
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
flutter analyze    # must be clean
flutter test       # must pass
```

Never run `flutter build` from `C:\Code\DocMe` — there is no `pubspec.yaml`
there, so it fails with "No pubspec.yaml file found".