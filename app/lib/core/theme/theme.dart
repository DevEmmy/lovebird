import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

class LBTheme {
  static TextTheme _text(Color ink, Color soft) {
    final body = GoogleFonts.plusJakartaSansTextTheme();
    final display = GoogleFonts.fraunces();
    return body.copyWith(
      displayLarge: display.copyWith(fontSize: 44, fontWeight: FontWeight.w600, color: ink, height: 1.1),
      displayMedium: display.copyWith(fontSize: 36, fontWeight: FontWeight.w600, color: ink, height: 1.1),
      displaySmall: display.copyWith(fontSize: 30, fontWeight: FontWeight.w600, color: ink, height: 1.15),
      headlineMedium: display.copyWith(fontSize: 26, fontWeight: FontWeight.w600, color: ink),
      headlineSmall: display.copyWith(fontSize: 22, fontWeight: FontWeight.w600, color: ink),
      titleLarge: body.titleLarge?.copyWith(fontSize: 19, fontWeight: FontWeight.w700, color: ink),
      titleMedium: body.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
      titleSmall: body.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w700, color: ink),
      bodyLarge: body.bodyLarge?.copyWith(fontSize: 16, color: ink, height: 1.5),
      bodyMedium: body.bodyMedium?.copyWith(fontSize: 14.5, color: ink, height: 1.45),
      bodySmall: body.bodySmall?.copyWith(fontSize: 12.5, color: soft, height: 1.4),
      labelLarge: body.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.1),
      labelMedium: body.labelMedium?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600, color: soft),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: LBColors.rose,
      brightness: Brightness.light,
    ).copyWith(
      primary: LBColors.rose,
      onPrimary: Colors.white,
      primaryContainer: LBColors.blush,
      onPrimaryContainer: LBColors.roseDeep,
      secondary: LBColors.blossom,
      surface: LBColors.cream,
      onSurface: LBColors.ink,
      onSurfaceVariant: LBColors.inkSoft,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: LBColors.mist,
      surfaceContainer: LBColors.blush,
      outline: const Color(0xFFD9BFCB),
      outlineVariant: LBColors.line,
      error: LBColors.danger,
    );
    return _base(scheme, _text(LBColors.ink, LBColors.inkSoft));
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: LBColors.rose,
      brightness: Brightness.dark,
    ).copyWith(
      primary: LBColors.nightPink,
      onPrimary: const Color(0xFF3A0D20),
      primaryContainer: const Color(0xFF5A1A36),
      onPrimaryContainer: const Color(0xFFFFD9E4),
      secondary: LBColors.blossom,
      surface: LBColors.night,
      onSurface: LBColors.nightInk,
      onSurfaceVariant: LBColors.nightInkSoft,
      surfaceContainerLowest: const Color(0xFF120A0E),
      surfaceContainerLow: LBColors.nightSurface,
      surfaceContainer: LBColors.nightRaised,
      outline: const Color(0xFF6E5260),
      outlineVariant: const Color(0xFF3E2A34),
      error: const Color(0xFFFFB4AB),
    );
    return _base(scheme, _text(LBColors.nightInk, LBColors.nightInkSoft));
  }

  static ThemeData _base(ColorScheme scheme, TextTheme text) {
    final radius = BorderRadius.circular(18);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: scheme.outlineVariant)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: scheme.outline),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 44), textStyle: text.labelLarge),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outline)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outlineVariant)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.primary, width: 2)),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: scheme.surfaceContainerLowest,
        selectedColor: scheme.primaryContainer,
        labelStyle: text.labelMedium?.copyWith(color: scheme.onSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium?.copyWith(color: scheme.onSurface)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        iconColor: scheme.primary,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      focusColor: scheme.primary.withValues(alpha: 0.16),
    );
  }
}
