import 'package:flutter/cupertino.dart';
import 'package:docme_ui/docme_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Hero surface: the next medication dose.
///
/// This is the one card on the Today screen that earns refractive glass —
/// it is the single most important thing on the page. Everything else stays
/// opaque per the iOS 26 material rule.
///
/// Only content goes inside; no `GlassButton`/`GlassSwitch`/`GlassSlider`
/// (that would be glass nested in glass).
class NextDoseCard extends StatelessWidget {
  const NextDoseCard({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      // premium is the correct tier for a static hero surface. Never place a
      // premium surface inside a scrolling viewport that repaints often —
      // GlassScaffold promotes bars for exactly this reason.
      quality: GlassQuality.premium,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: DocMeColors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'NEXT DOSE · IN 42 MIN',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: DocMeColors.amber,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Metformin',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            '500 mg · 1 tablet · with food',
            style: TextStyle(fontSize: 13.5, color: DocMeColors.inkDarkMuted),
          ),
          const SizedBox(height: 3),
          const Text(
            'Prescribed by Dr. Amara Osei',
            style: TextStyle(fontSize: 12, color: DocMeColors.inkDarkMuted),
          ),
          const SizedBox(height: 20),
          const Row(
            children: [
              Expanded(
                child: _DoseAction(
                  label: 'Taken',
                  icon: CupertinoIcons.checkmark_alt,
                  accent: DocMeColors.mint,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _DoseAction(
                  label: 'Skip',
                  icon: CupertinoIcons.forward_end_alt,
                  accent: DocMeColors.inkDarkMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Plain (non-refractive) button styled to sit inside the glass hero card.
///
/// Deliberately not `GlassButton`: putting a refractive control inside a
/// refractive card double-refracts, distorts, and clips the press animation.
class _DoseAction extends StatelessWidget {
  const _DoseAction({
    required this.label,
    required this.icon,
    required this.accent,
  });

  final String label;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // TODO(M3): write medication_logs row.
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.32), width: 0.8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: accent),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}