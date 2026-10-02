import 'package:flutter/cupertino.dart';

/// DocMe brand palette.
///
/// The backdrop is deliberately deep and saturated: refractive glass only
/// reads as "glass" when there is rich colour behind it to bend. Light pastel
/// backgrounds make refraction invisible.
abstract final class DocMeColors {
  /// App backdrop, dark. Order is top-left -> bottom-right.
  static const backdropDark = <Color>[
    Color(0xFF070B1F),
    Color(0xFF141033),
    Color(0xFF062028),
    Color(0xFF0B0718),
  ];

  /// App backdrop, light.
  static const backdropLight = <Color>[
    Color(0xFFDCE7FF),
    Color(0xFFEADFFF),
    Color(0xFFD7F2F4),
    Color(0xFFF3E8FF),
  ];

  /// Primary accent — clinical, calm, trustworthy.
  static const mint = Color(0xFF4FE3C1);
  static const mintDeep = Color(0xFF17B39A);

  /// Medication / adherence accent.
  static const amber = Color(0xFFFFB020);

  /// Emergency + destructive.
  static const coral = Color(0xFFFF5C7A);

  /// Secondary categorical accent for specialties and tags.
  static const violet = Color(0xFF9B8CFF);
  static const sky = Color(0xFF62B8FF);

  /// On-surface text, dark theme.
  static const inkDark = Color(0xFFF4F6FF);
  static const inkDarkMuted = Color(0xFFA8B0CE);

  /// On-surface text, light theme.
  static const inkLight = Color(0xFF131735);
  static const inkLightMuted = Color(0xFF5A6083);

  /// Hairline border shared by every surface in the app.
  static const hairlineDark = Color(0x24FFFFFF);
  static const hairlineLight = Color(0x1A0B1030);
}

/// Accent role → colour, used consistently for urgency and category cues.
enum DocMeAccent { primary, medication, emergency, info, neutral }

extension DocMeAccentColor on DocMeAccent {
  Color get color {
    switch (this) {
      case DocMeAccent.primary:
        return DocMeColors.mint;
      case DocMeAccent.medication:
        return DocMeColors.amber;
      case DocMeAccent.emergency:
        return DocMeColors.coral;
      case DocMeAccent.info:
        return DocMeColors.sky;
      case DocMeAccent.neutral:
        return DocMeColors.violet;
    }
  }
}