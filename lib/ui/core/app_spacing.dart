/// Spacing and radius tokens, so padding is consistent across screens.
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 40.0;

  static const radius = 12.0;
  static const radiusSm = 6.0;

  // Control sizing — one source of truth so every button / field / chip in the
  // app is the same height.
  static const controlHeight = 34.0; // buttons, fields, chips
  static const iconButtonSize = 32.0; // tappable box of an icon button
  static const iconSize = 18.0; // the glyph inside it
}
