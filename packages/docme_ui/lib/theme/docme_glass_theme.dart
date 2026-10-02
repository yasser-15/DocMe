import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'docme_palette.dart';

/// App-wide glass theme.
///
/// Dark is the primary experience: refraction needs a saturated, deep backdrop
/// to be visible. Light mode is a supported variant, not the design target.
GlassThemeData buildDocMeGlassTheme() {
  return GlassThemeData(
    light: GlassThemeVariant(
      settings: GlassThemeSettings(
        thickness: 24,
        blur: 10,
        fresnelStrength: 0.5,
        saturation: 1.1,
        glassColor: const Color(0x33FFFFFF),
      ),
      quality: GlassQuality.standard,
      glowColors: const GlassGlowColors(
        primary: DocMeColors.mintDeep,
        glowBlurRadius: 12,
        glowSpreadRadius: 0.2,
      ),
    ),
    dark: GlassThemeVariant(
      settings: GlassThemeSettings(
        thickness: 40,
        blur: 16,
        fresnelStrength: 0.75,
        saturation: 1.25,
        glassColor: const Color(0x1AFFFFFF),
      ),
      quality: GlassQuality.standard,
      glowColors: const GlassGlowColors(
        primary: DocMeColors.mint,
        glowBlurRadius: 14,
        glowSpreadRadius: 0.22,
      ),
    ),
  );
}

/// The gradient every screen sits on.
///
/// Glass refracts what is behind it. Without a controlled, colourful backdrop
/// glass surfaces render flat and the whole design language collapses — so this
/// is not decoration, it is a rendering requirement.
class DocMeBackdrop extends StatelessWidget {
  const DocMeBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final colors = brightness == Brightness.dark
        ? DocMeColors.backdropDark
        : DocMeColors.backdropLight;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: const _AmbientGlow(),
    );
  }
}

/// Two slow-drifting radial blooms that give the refraction something to bend.
class _AmbientGlow extends StatefulWidget {
  const _AmbientGlow();

  @override
  State<_AmbientGlow> createState() => _AmbientGlowState();
}

class _AmbientGlowState extends State<_AmbientGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            _bloom(
              alignment: Alignment(-0.7 + 0.25 * t, -0.6),
              color: DocMeColors.mint.withValues(alpha: 0.16),
              radius: 1.05,
            ),
            _bloom(
              alignment: Alignment(0.8, 0.1 + 0.2 * t),
              color: DocMeColors.violet.withValues(alpha: 0.18),
              radius: 1.15,
            ),
            _bloom(
              alignment: Alignment(-0.1, 0.9 - 0.15 * t),
              color: DocMeColors.coral.withValues(alpha: 0.10),
              radius: 0.9,
            ),
          ],
        );
      },
    );
  }

  Widget _bloom({
    required Alignment alignment,
    required Color color,
    required double radius,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: alignment,
          radius: radius,
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}