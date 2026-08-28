import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifedna/core/theme/ld_colors.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/theme/ld_typography.dart';

/// Builds the Material 3 [ThemeData] for each brightness, with the LifeDNA
/// design system attached as theme extensions.
abstract final class AppTheme {
  static ThemeData dark() => _build(LdColors.dark, Brightness.dark);
  static ThemeData light() => _build(LdColors.light, Brightness.light);

  static ThemeData _build(LdColors c, Brightness brightness) {
    const type = LdTypography.standard;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.textOnPrimary,
      primaryContainer: c.primaryMuted,
      onPrimaryContainer: c.primary,
      secondary: c.secondary,
      onSecondary: c.textOnPrimary,
      secondaryContainer: c.secondaryMuted,
      onSecondaryContainer: c.secondary,
      tertiary: c.accent,
      onTertiary: c.textOnPrimary,
      error: c.danger,
      onError: c.textOnPrimary,
      surface: c.surface,
      onSurface: c.textPrimary,
      surfaceContainerHighest: c.surfaceHighest,
      onSurfaceVariant: c.textSecondary,
      outline: c.border,
      outlineVariant: c.borderStrong,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      splashFactory: InkSparkle.splashFactory,

      // Every widget reads colour through these two extensions.
      extensions: <ThemeExtension<dynamic>>[c, type],

      textTheme: TextTheme(
        displayLarge: type.displayXL.copyWith(color: c.textPrimary),
        displayMedium: type.displayL.copyWith(color: c.textPrimary),
        displaySmall: type.displayM.copyWith(color: c.textPrimary),
        headlineLarge: type.headlineL.copyWith(color: c.textPrimary),
        headlineMedium: type.headlineM.copyWith(color: c.textPrimary),
        titleLarge: type.titleL.copyWith(color: c.textPrimary),
        titleMedium: type.titleM.copyWith(color: c.textPrimary),
        bodyLarge: type.bodyL.copyWith(color: c.textPrimary),
        bodyMedium: type.bodyM.copyWith(color: c.textSecondary),
        bodySmall: type.bodyS.copyWith(color: c.textSecondary),
        labelLarge: type.label.copyWith(color: c.textPrimary),
        labelMedium: type.labelMono.copyWith(color: c.textTertiary),
        labelSmall: type.caption.copyWith(color: c.textTertiary),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: type.headlineM.copyWith(color: c.textPrimary),
        iconTheme: IconThemeData(color: c.textPrimary),
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),

      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LdRadius.m),
          side: BorderSide(color: c.border),
        ),
      ),

      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.textOnPrimary,
          disabledBackgroundColor: c.surfaceHighest,
          disabledForegroundColor: c.textDisabled,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LdRadius.s + 2),
          ),
          textStyle: type.titleM,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          side: BorderSide(color: c.borderStrong),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LdRadius.s + 2),
          ),
          textStyle: type.titleM,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          textStyle: type.titleM,
          minimumSize: const Size(LdTouch.min, LdTouch.min),
        ),
      ),

      iconTheme: IconThemeData(color: c.textSecondary, size: 24),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: LdSpacing.s4,
          vertical: LdSpacing.s3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LdRadius.s),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LdRadius.s),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LdRadius.s),
          borderSide: BorderSide(color: c.borderFocus, width: 2),
        ),
        hintStyle: type.bodyM.copyWith(color: c.textTertiary),
        labelStyle: type.label.copyWith(color: c.textSecondary),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(LdRadius.l)),
        ),
        showDragHandle: true,
        dragHandleColor: c.borderStrong,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.primaryMuted,
        height: LdTouch.gym,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? type.caption.copyWith(
                  color: c.primary,
                  fontWeight: FontWeight.w600,
                )
              : type.caption.copyWith(color: c.textTertiary),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? c.primary
                : c.textTertiary,
            size: 24,
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceElevated,
        selectedColor: c.primaryMuted,
        side: BorderSide(color: c.border),
        labelStyle: type.bodyS.copyWith(color: c.textSecondary),
        secondaryLabelStyle: type.bodyS.copyWith(color: c.primary),
        padding: const EdgeInsets.symmetric(
          horizontal: LdSpacing.s3,
          vertical: LdSpacing.s2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LdRadius.xs),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.border,
        circularTrackColor: c.border,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceHighest,
        contentTextStyle: type.bodyM.copyWith(color: c.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LdRadius.s),
        ),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
        contentPadding: const EdgeInsets.symmetric(horizontal: LdSpacing.s4),
        minVerticalPadding: LdSpacing.s2,
      ),
    );
  }
}

/// The only sanctioned way to obtain design-system values in a widget.
extension LdThemeX on BuildContext {
  LdColors get ldColors =>
      Theme.of(this).extension<LdColors>() ?? LdColors.dark;

  LdTypography get ldType =>
      Theme.of(this).extension<LdTypography>() ?? LdTypography.standard;

  /// True when the user has asked the system to reduce motion. Every animated
  /// surface must honour this (docs/04 §6.3).
  bool get reduceMotion => MediaQuery.of(this).disableAnimations;
}
