import 'package:flutter/material.dart';

/// The LifeDNA type scale (docs/04-design-system.md §3).
///
/// Metric values use tabular figures so a changing number never causes a layout
/// shift — a rest timer counting down must not make the row jitter.
@immutable
class LdTypography extends ThemeExtension<LdTypography> {
  const LdTypography({
    required this.displayXL,
    required this.displayL,
    required this.displayM,
    required this.headlineL,
    required this.headlineM,
    required this.titleL,
    required this.titleM,
    required this.bodyL,
    required this.bodyM,
    required this.bodyS,
    required this.label,
    required this.labelMono,
    required this.caption,
  });

  final TextStyle displayXL;
  final TextStyle displayL;
  final TextStyle displayM;
  final TextStyle headlineL;
  final TextStyle headlineM;
  final TextStyle titleL;
  final TextStyle titleM;
  final TextStyle bodyL;
  final TextStyle bodyM;
  final TextStyle bodyS;
  final TextStyle label;
  final TextStyle labelMono;
  final TextStyle caption;

  /// Tabular figures. Applied to every numeric value in the product.
  static const List<FontFeature> tabular = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  static const LdTypography standard = LdTypography(
    displayXL: TextStyle(
      fontSize: 56,
      height: 1.0,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.12,
      fontFeatures: tabular,
    ),
    displayL: TextStyle(
      fontSize: 44,
      height: 1.045,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.88,
      fontFeatures: tabular,
    ),
    displayM: TextStyle(
      fontSize: 34,
      height: 1.118,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.51,
      fontFeatures: tabular,
    ),
    headlineL: TextStyle(
      fontSize: 28,
      height: 1.214,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.28,
    ),
    headlineM: TextStyle(
      fontSize: 22,
      height: 1.273,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.11,
    ),
    titleL: TextStyle(fontSize: 18, height: 1.333, fontWeight: FontWeight.w600),
    titleM: TextStyle(fontSize: 16, height: 1.375, fontWeight: FontWeight.w600),
    bodyL: TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w400),
    bodyM: TextStyle(fontSize: 14, height: 1.429, fontWeight: FontWeight.w400),
    bodyS: TextStyle(fontSize: 13, height: 1.385, fontWeight: FontWeight.w400),
    label: TextStyle(
      fontSize: 12,
      height: 1.333,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.24,
    ),
    // The technical eyebrow: uppercase, wide-tracked, monospaced.
    labelMono: TextStyle(
      fontSize: 11,
      height: 1.273,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.88,
    ),
    caption: TextStyle(fontSize: 11, height: 1.273, fontWeight: FontWeight.w400),
  );

  @override
  LdTypography copyWith({
    TextStyle? displayXL,
    TextStyle? displayL,
    TextStyle? displayM,
    TextStyle? headlineL,
    TextStyle? headlineM,
    TextStyle? titleL,
    TextStyle? titleM,
    TextStyle? bodyL,
    TextStyle? bodyM,
    TextStyle? bodyS,
    TextStyle? label,
    TextStyle? labelMono,
    TextStyle? caption,
  }) {
    return LdTypography(
      displayXL: displayXL ?? this.displayXL,
      displayL: displayL ?? this.displayL,
      displayM: displayM ?? this.displayM,
      headlineL: headlineL ?? this.headlineL,
      headlineM: headlineM ?? this.headlineM,
      titleL: titleL ?? this.titleL,
      titleM: titleM ?? this.titleM,
      bodyL: bodyL ?? this.bodyL,
      bodyM: bodyM ?? this.bodyM,
      bodyS: bodyS ?? this.bodyS,
      label: label ?? this.label,
      labelMono: labelMono ?? this.labelMono,
      caption: caption ?? this.caption,
    );
  }

  @override
  LdTypography lerp(ThemeExtension<LdTypography>? other, double t) {
    if (other is! LdTypography) return this;
    TextStyle l(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return LdTypography(
      displayXL: l(displayXL, other.displayXL),
      displayL: l(displayL, other.displayL),
      displayM: l(displayM, other.displayM),
      headlineL: l(headlineL, other.headlineL),
      headlineM: l(headlineM, other.headlineM),
      titleL: l(titleL, other.titleL),
      titleM: l(titleM, other.titleM),
      bodyL: l(bodyL, other.bodyL),
      bodyM: l(bodyM, other.bodyM),
      bodyS: l(bodyS, other.bodyS),
      label: l(label, other.label),
      labelMono: l(labelMono, other.labelMono),
      caption: l(caption, other.caption),
    );
  }
}
