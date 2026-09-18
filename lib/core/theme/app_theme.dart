import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Material 3 theme for ScreenSift.
///
/// Two rules drive every choice below:
///  * white canvas, teal accent, dark-slate ink;
///  * zero elevation on content surfaces — structure comes from 1px borders
///    and spacing, never from shadows, so the UI reads as "parsed data".
abstract final class AppTheme {
  static const double radiusSm = 10;
  static const double radiusMd = 16;
  static const double radiusLg = 22;
  static const double gutter = 20;

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppPalette.teal,
      onPrimary: AppPalette.white,
      primaryContainer: AppPalette.tealTint,
      onPrimaryContainer: AppPalette.tealDeep,
      secondary: AppPalette.slateSoft,
      onSecondary: AppPalette.white,
      secondaryContainer: AppPalette.canvasAlt,
      onSecondaryContainer: AppPalette.slate,
      tertiary: AppPalette.info,
      onTertiary: AppPalette.white,
      tertiaryContainer: AppPalette.infoTint,
      onTertiaryContainer: AppPalette.slate,
      error: AppPalette.danger,
      onError: AppPalette.white,
      errorContainer: AppPalette.dangerTint,
      onErrorContainer: AppPalette.danger,
      surface: AppPalette.white,
      onSurface: AppPalette.slate,
      surfaceContainerLowest: AppPalette.white,
      surfaceContainerLow: AppPalette.canvas,
      surfaceContainer: AppPalette.canvasAlt,
      surfaceContainerHigh: AppPalette.border,
      surfaceContainerHighest: AppPalette.borderStrong,
      onSurfaceVariant: AppPalette.slateMuted,
      outline: AppPalette.borderStrong,
      outlineVariant: AppPalette.border,
      shadow: Color(0x14000000),
      scrim: Color(0x99000000),
      inverseSurface: AppPalette.slateSoft,
      onInverseSurface: AppPalette.white,
      inversePrimary: AppPalette.tealTintStrong,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppPalette.canvas,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppPalette.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppPalette.slate,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppPalette.slate,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppPalette.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: const BorderSide(color: AppPalette.border),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppPalette.white,
        selectedItemColor: AppPalette.tealDeep,
        unselectedItemColor: AppPalette.slateFaint,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        showUnselectedLabels: true,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        unselectedLabelStyle:
            TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppPalette.tealDeep,
          foregroundColor: AppPalette.white,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppPalette.tealDeep,
          foregroundColor: AppPalette.white,
          elevation: 0,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm + 2),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppPalette.slateSoft,
          minimumSize: const Size(0, 46),
          side: const BorderSide(color: AppPalette.borderStrong),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm + 2),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppPalette.tealDeep,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppPalette.white,
        selectedColor: AppPalette.tealTint,
        surfaceTintColor: Colors.transparent,
        side: const BorderSide(color: AppPalette.border),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: AppPalette.slateSoft,
        ),
        secondaryLabelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: AppPalette.tealDeep,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppPalette.slate,
        unselectedLabelColor: AppPalette.slateFaint,
        dividerColor: AppPalette.border,
        indicatorColor: AppPalette.teal,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle:
            TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      dividerTheme: const DividerThemeData(
        color: AppPalette.border,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppPalette.white,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppPalette.white,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: AppPalette.borderStrong,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppPalette.slateSoft,
        contentTextStyle: const TextStyle(
          color: AppPalette.white,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm + 2),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppPalette.white
              : AppPalette.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppPalette.teal
              : AppPalette.borderStrong,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 4),
        iconColor: AppPalette.slateMuted,
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    return base
        .copyWith(
          displaySmall: base.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
            color: AppPalette.slate,
          ),
          headlineMedium: base.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
            color: AppPalette.slate,
          ),
          headlineSmall: base.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: AppPalette.slate,
          ),
          titleLarge: base.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: AppPalette.slate,
          ),
          titleMedium: base.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppPalette.slate,
          ),
          titleSmall: base.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppPalette.slateSoft,
          ),
          bodyLarge: base.bodyLarge?.copyWith(
            fontSize: 15,
            height: 1.45,
            color: AppPalette.slateSoft,
          ),
          bodyMedium: base.bodyMedium?.copyWith(
            fontSize: 14,
            height: 1.45,
            color: AppPalette.slateSoft,
          ),
          bodySmall: base.bodySmall?.copyWith(
            fontSize: 12.5,
            height: 1.4,
            color: AppPalette.slateMuted,
          ),
          labelLarge: base.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
          labelSmall: base.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppPalette.slateFaint,
          ),
        )
        .apply(
          fontFamily: 'Roboto',
          displayColor: AppPalette.slate,
          bodyColor: AppPalette.slateSoft,
        );
  }
}
