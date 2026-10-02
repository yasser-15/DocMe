/// DocMe design system.
///
/// Rule enforced by this package: **glass is the navigation layer, content stays
/// opaque.** Use `GlassScaffold` + `GlassAppBar` + `GlassTabBar` for chrome and
/// `ContentCard` for content. Do not nest glass inside glass.
///
/// See `docs/PLAN.md` §8 and `.agents/skills/liquid-glass-widgets/SKILL.md`.
library;

export 'theme/docme_glass_theme.dart';
export 'theme/docme_palette.dart';
export 'widgets/content_card.dart';