/// Spacing, radius and motion tokens (docs/04-design-system.md §4, §6).
///
/// These are compile-time constants rather than a theme extension because they
/// never vary by theme — only colour does.
abstract final class LdSpacing {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s7 = 32;
  static const double s8 = 40;
  static const double s9 = 48;
  static const double s10 = 64;
  static const double s11 = 80;
  static const double s12 = 96;

  /// Horizontal screen padding. Never less than this.
  static const double screenH = s4;

  /// Vertical gap between stacked cards.
  static const double cardGap = s3;

  /// Trailing scroll padding so the last item clears the nav bar and any FAB.
  static const double scrollBottom = s10 + s6;
}

abstract final class LdRadius {
  static const double xs = 6;
  static const double s = 10;

  /// The signature card radius.
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
  static const double full = 999;
}

abstract final class LdMotion {
  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration ring = Duration(milliseconds: 800);
  static const Duration count = Duration(milliseconds: 600);
}

/// Minimum interactive sizes (docs/04 §11).
abstract final class LdTouch {
  /// WCAG / Material minimum.
  static const double min = 48;

  /// Live Gym Mode minimum — operated one-handed, at arm's length, mid-set.
  static const double gym = 64;

  /// The primary Live Gym action.
  static const double gymPrimary = 72;
}
