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