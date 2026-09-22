import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const primary = Color(0xFF4F46E5);
  static const accent = Color(0xFF14B8A6);
  static const darkBg = Color(0xFF121212);
  static const darkCard = Color(0xFF1E1E1E);
  static const lightBg = Color(0xFFF6F7FB);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
}

/// system → light → dark, toggled from the home header. In-memory only.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: Colors.white,
      surface: isDark ? AppColors.darkBg : AppColors.lightBg,
      error: AppColors.danger,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);

    // Inter for body copy, Poppins for headings.
    final body = GoogleFonts.interTextTheme(base.textTheme);
    TextStyle? heading(TextStyle? s, FontWeight w) =>
        GoogleFonts.poppins(textStyle: s, fontWeight: w);
    final text = body.copyWith(
      displayLarge: heading(body.displayLarge, FontWeight.w700),
      displayMedium: heading(body.displayMedium, FontWeight.w700),
      displaySmall: heading(body.displaySmall, FontWeight.w700),
      headlineLarge: heading(body.headlineLarge, FontWeight.w700),
      headlineMedium: heading(body.headlineMedium, FontWeight.w700),
      headlineSmall: heading(body.headlineSmall, FontWeight.w700),
      titleLarge: heading(body.titleLarge, FontWeight.w600),
      titleMedium: heading(body.titleMedium, FontWeight.w600),
    );

    final cardColor = isDark ? AppColors.darkCard : Colors.white;
    final fieldColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF1F2F6);

    return base.copyWith(
      scaffoldBackgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      textTheme: text,
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      bottomAppBarTheme: BottomAppBarThemeData(color: cardColor, elevation: 8),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
      }),
    );
  }
}
