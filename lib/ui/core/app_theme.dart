import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The app's single theme. Dark, Material 3, with the MozCut accent.
abstract final class AppTheme {
  static ThemeData get dark =>
      ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          surface: AppColors.surface,
        ),
      );
}
