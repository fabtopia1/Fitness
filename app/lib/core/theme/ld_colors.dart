import 'package:flutter/material.dart';

/// The complete LifeDNA colour system, exposed as a [ThemeExtension].
///
/// Widgets never reference a hex literal or a `Colors.*` constant. They obtain
/// every colour from `context.ldColors`, which is what allows the entire app to
/// switch themes without a single conditional in a widget.
///
/// See docs/04-design-system.md §2.
@immutable
class LdColors extends ThemeExtension<LdColors> {
  const LdColors({
    required this.bg,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceHighest,
    required this.border,
    required this.borderStrong,
    required this.borderFocus,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.textOnPrimary,
    required this.primary,
    required this.primaryHover,
    required this.primaryPressed,
    required this.primaryMuted,
    required this.secondary,
    required this.secondaryMuted,
    required this.accent,
    required this.accentMuted,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.water,
    required this.recoveryLow,
    required this.recoveryModerate,
    required this.recoveryHigh,
  });

  // Surfaces
  final Color bg;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceHighest;

  // Borders
  final Color border;
  final Color borderStrong;
  final Color borderFocus;

  // Text
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;
  final Color textOnPrimary;

  // Brand
  final Color primary;
  final Color primaryHover;
  final Color primaryPressed;
  final Color primaryMuted;
  final Color secondary;
  final Color secondaryMuted;
  final Color accent;
  final Color accentMuted;

  // Semantic
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  // Data encoding — these are FIXED. A macro's colour never changes meaning.
  final Color calories;
  final Color protein;
  final Color carbs;
  final Color fat;
  final Color water;

  // Recovery bands
  final Color recoveryLow;
  final Color recoveryModerate;
  final Color recoveryHigh;

  /// The default theme. Every design decision is made here first.
  static const LdColors dark = LdColors(
    bg: Color(0xFF05070D),
    surface: Color(0xFF0A0E17),
    surfaceElevated: Color(0xFF111725),
    surfaceHighest: Color(0xFF18202F),
    border: Color(0xFF1C2536),
    borderStrong: Color(0xFF2A3547),
    borderFocus: Color(0xFF0066FF),
    textPrimary: Color(0xFFF2F5FA),
    textSecondary: Color(0xFF9BA8BE),
    textTertiary: Color(0xFF61708A),
    textDisabled: Color(0xFF3A455A),
    textOnPrimary: Color(0xFFFFFFFF),
    primary: Color(0xFF0066FF),
    primaryHover: Color(0xFF1F7BFF),
    primaryPressed: Color(0xFF0052CC),
    primaryMuted: Color(0x1F0066FF),
    secondary: Color(0xFF00D1B2),
    secondaryMuted: Color(0x1F00D1B2),
    accent: Color(0xFFFFB800),
    accentMuted: Color(0x1FFFB800),
    success: Color(0xFF22C55E),
    warning: Color(0xFFFFB800),
    danger: Color(0xFFFF4D5E),
    info: Color(0xFF38BDF8),
    calories: Color(0xFF0066FF),
    protein: Color(0xFF00D1B2),
    carbs: Color(0xFFFFB800),
    fat: Color(0xFFFF7A45),
    water: Color(0xFF38BDF8),
    recoveryLow: Color(0xFFFF4D5E),
    recoveryModerate: Color(0xFFFFB800),
    recoveryHigh: Color(0xFF22C55E),
  );

  /// Light theme. Brand colours are darkened to hold AA contrast on white.
  static const LdColors light = LdColors(
    bg: Color(0xFFF5F7FB),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceHighest: Color(0xFFEEF2F8),
    border: Color(0xFFE2E8F2),
    borderStrong: Color(0xFFCBD5E5),
    borderFocus: Color(0xFF0052CC),
    textPrimary: Color(0xFF0A0E17),
    textSecondary: Color(0xFF4A5568),
    textTertiary: Color(0xFF718096),
    textDisabled: Color(0xFFA0AEC0),
    textOnPrimary: Color(0xFFFFFFFF),
    primary: Color(0xFF0052CC),
    primaryHover: Color(0xFF0066FF),
    primaryPressed: Color(0xFF003D99),
    primaryMuted: Color(0x140052CC),
    secondary: Color(0xFF00A88F),
    secondaryMuted: Color(0x1400A88F),
    accent: Color(0xFFB37F00),
    accentMuted: Color(0x14B37F00),
    success: Color(0xFF16A34A),
    warning: Color(0xFFB37F00),
    danger: Color(0xFFDC2626),
    info: Color(0xFF0284C7),
    calories: Color(0xFF0052CC),
    protein: Color(0xFF00A88F),
    carbs: Color(0xFFB37F00),
    fat: Color(0xFFE05A1F),
    water: Color(0xFF0284C7),
    recoveryLow: Color(0xFFDC2626),
    recoveryModerate: Color(0xFFB37F00),
    recoveryHigh: Color(0xFF16A34A),
  );

  /// Resolves the colour for a recovery score band.
  Color recoveryBandColor(int score) {
    if (score <= 33) return recoveryLow;
    if (score <= 66) return recoveryModerate;
    return recoveryHigh;
  }

  @override
  LdColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceHighest,
    Color? border,
    Color? borderStrong,
    Color? borderFocus,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? textOnPrimary,
    Color? primary,
    Color? primaryHover,
    Color? primaryPressed,
    Color? primaryMuted,
    Color? secondary,
    Color? secondaryMuted,
    Color? accent,
    Color? accentMuted,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? calories,
    Color? protein,
    Color? carbs,
    Color? fat,
    Color? water,
    Color? recoveryLow,
    Color? recoveryModerate,
    Color? recoveryHigh,
  }) {
    return LdColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceHighest: surfaceHighest ?? this.surfaceHighest,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      borderFocus: borderFocus ?? this.borderFocus,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
      textOnPrimary: textOnPrimary ?? this.textOnPrimary,
      primary: primary ?? this.primary,
      primaryHover: primaryHover ?? this.primaryHover,
      primaryPressed: primaryPressed ?? this.primaryPressed,
      primaryMuted: primaryMuted ?? this.primaryMuted,
      secondary: secondary ?? this.secondary,
      secondaryMuted: secondaryMuted ?? this.secondaryMuted,
      accent: accent ?? this.accent,
      accentMuted: accentMuted ?? this.accentMuted,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
      water: water ?? this.water,
      recoveryLow: recoveryLow ?? this.recoveryLow,
      recoveryModerate: recoveryModerate ?? this.recoveryModerate,
      recoveryHigh: recoveryHigh ?? this.recoveryHigh,
    );
  }

  @override
  LdColors lerp(ThemeExtension<LdColors>? other, double t) {
    if (other is! LdColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return LdColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surfaceElevated: l(surfaceElevated, other.surfaceElevated),
      surfaceHighest: l(surfaceHighest, other.surfaceHighest),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      borderFocus: l(borderFocus, other.borderFocus),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      textDisabled: l(textDisabled, other.textDisabled),
      textOnPrimary: l(textOnPrimary, other.textOnPrimary),
      primary: l(primary, other.primary),
      primaryHover: l(primaryHover, other.primaryHover),
      primaryPressed: l(primaryPressed, other.primaryPressed),
      primaryMuted: l(primaryMuted, other.primaryMuted),
      secondary: l(secondary, other.secondary),
      secondaryMuted: l(secondaryMuted, other.secondaryMuted),
      accent: l(accent, other.accent),
      accentMuted: l(accentMuted, other.accentMuted),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      info: l(info, other.info),
      calories: l(calories, other.calories),
      protein: l(protein, other.protein),
      carbs: l(carbs, other.carbs),
      fat: l(fat, other.fat),
      water: l(water, other.water),
      recoveryLow: l(recoveryLow, other.recoveryLow),
      recoveryModerate: l(recoveryModerate, other.recoveryModerate),
      recoveryHigh: l(recoveryHigh, other.recoveryHigh),
    );
  }
}
