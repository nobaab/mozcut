import 'package:flutter/material.dart';

/// The app's colour tokens. One place that knows what "surface" or "accent"
/// means, so a theme change is one edit rather than a hunt through widgets.
abstract final class AppColors {
  static const bg = Color(0xFF17181C);
  static const surface = Color(0xFF1F2026);
  static const panel = Color(0xFF131418);
  static const well = Color(0xFF0C0D10);
  static const accent = Color(0xFF0568FD);
  static const line = Color(0x1AFFFFFF); // white @ 10%
}
