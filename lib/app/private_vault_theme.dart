import 'package:flutter/material.dart';

abstract final class PrivateVaultTheme {
  static const Duration motion = Duration(milliseconds: 180);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static Duration motionDuration(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : motion;

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: dark ? const Color(0xFF78AEB3) : const Color(0xFF315E63),
          brightness: brightness,
        ).copyWith(
          surface: dark ? const Color(0xFF101718) : const Color(0xFFF4F7F6),
          surfaceContainerLow: dark
              ? const Color(0xFF172021)
              : const Color(0xFFEDF2F0),
          surfaceContainer: dark
              ? const Color(0xFF1B2526)
              : const Color(0xFFE7EEEC),
          outlineVariant: dark
              ? const Color(0xFF344445)
              : const Color(0xFFCBD8D5),
        );

    final radius = BorderRadius.circular(16);
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    );
  }
}
