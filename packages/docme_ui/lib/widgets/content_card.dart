import 'dart:ui';

import 'package:flutter/cupertino.dart';

import '../theme/docme_palette.dart';

/// The workhorse content surface.
///
/// Deliberately **not** refractive glass. Per Apple's own iOS 26 rule, glass is
/// the navigation layer and content stays opaque. This widget gives content the
/// same acrylic translucency using a cheap `BackdropFilter` instead of a glass
/// shader — visually consistent with the chrome, but with none of the
/// refraction or per-frame shader cost.
///
/// Do not nest this inside a `GlassCard`; that is the glass-in-glass
/// anti-pattern. Content surfaces live on the page, chrome floats above them.
class ContentCard extends StatelessWidget {
  const ContentCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.onTap,
    this.accent,
    this.blur = 18,
    this.elevated = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;

  /// When set, tints the surface and paints a leading accent rail.
  final DocMeAccent? accent;

  /// Gaussian sigma for the acrylic blur. Pass `0` in dense scrolling lists to
  /// drop the `saveLayer` entirely — a blurred card per row is the single
  /// easiest way to destroy scroll performance.
  final double blur;

  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;

    final surface = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0x2EFFFFFF), Color(0x14FFFFFF)]
              : const [Color(0xD9FFFFFF), Color(0xBFFFFFFF)],
        ),
        border: Border.all(
          color: dark ? DocMeColors.hairlineDark : DocMeColors.hairlineLight,
          width: 0.8,
        ),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: const Color(0x33000000),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: accent == null
          ? child
          : IntrinsicHeight(
              // The accent rule spans the full card height, which needs a
              // stretched Row. Inside a scrolling ListView the height is
              // unbounded, so `stretch` alone would force infinite height.
              // IntrinsicHeight is the correct fix; it costs one extra layout
              // pass, which is acceptable because only accent cards pay it.
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 3,
                    margin: const EdgeInsets.only(right: 14),
                    decoration: BoxDecoration(
                      color: accent!.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
    );

    Widget result = surface;
    if (blur > 0) {
      result = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: surface,
        ),
      );
    }
    if (margin != null) {
      result = Padding(padding: margin!, child: result);
    }
    if (onTap != null) {
      result = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: result,
      );
    }
    return result;
  }
}

/// Small uppercase section label used above grouped content.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final fg = dark ? DocMeColors.inkDarkMuted : DocMeColors.inkLightMuted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.9,
                color: fg,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Placeholder for surfaces with no data yet.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final fg = dark ? DocMeColors.inkDark : DocMeColors.inkLight;
    final muted = dark ? DocMeColors.inkDarkMuted : DocMeColors.inkLightMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: muted.withValues(alpha: 0.7)),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.45, color: muted),
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

/// Compact labelled metric, used for counts and adherence figures.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.accent = DocMeAccent.primary,
  });

  final String label;
  final String value;
  final DocMeAccent accent;

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final fg = dark ? DocMeColors.inkDark : DocMeColors.inkLight;
    final muted = dark ? DocMeColors.inkDarkMuted : DocMeColors.inkLightMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: fg,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.color,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontSize: 12.5, color: muted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}