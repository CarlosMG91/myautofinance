import 'package:flutter/material.dart';

import 'tokens.dart';

abstract final class AfTheme {
  static ThemeData light({bool highContrast = false}) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AfTokens.accent,
          brightness: Brightness.light,
        ).copyWith(
          primary: AfTokens.accent,
          onPrimary: AfTokens.onAccent,
          secondary: AfTokens.seriesBudget,
          onSecondary: AfTokens.onAccent,
          surface: AfTokens.surface,
          onSurface: AfTokens.text,
          onSurfaceVariant: AfTokens.muted,
          outline: highContrast ? AfTokens.text : AfTokens.controlBorder,
          error: AfTokens.error,
          onError: AfTokens.onAccent,
          surfaceTint: Colors.transparent,
        );
    const numeric = [FontFeature.tabularFigures()];
    const text = TextTheme(
      displaySmall: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        height: 1.15,
        fontFeatures: numeric,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.5,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.5,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5),
      bodyMedium: TextStyle(fontSize: 16, height: 1.5),
      bodySmall: TextStyle(fontSize: 14, height: 1.5),
      labelLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.5,
      ),
      labelMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.5,
      ),
      labelSmall: TextStyle(fontSize: 14, height: 1.5),
    );
    ButtonStyle button(Color foreground, Color background) => ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.disabled) ? AfTokens.muted : foreground,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? AfTokens.surfaceSubtle
            : background,
      ),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? AfTokens.focus.withValues(alpha: .14)
            : null,
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? const BorderSide(color: AfTokens.focus, width: 3)
            : BorderSide(
                color: foreground == AfTokens.onAccent
                    ? AfTokens.accent
                    : AfTokens.controlBorder,
              ),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: AfTokens.family,
      colorScheme: scheme,
      scaffoldBackgroundColor: AfTokens.canvas,
      textTheme: text.apply(
        bodyColor: AfTokens.text,
        displayColor: AfTokens.text,
        fontFamily: AfTokens.family,
      ),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      dividerColor: AfTokens.border,
      focusColor: AfTokens.focus,
      filledButtonTheme: FilledButtonThemeData(
        style: button(AfTokens.onAccent, AfTokens.accent),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: button(AfTokens.text, AfTokens.surface),
      ),
      textButtonTheme: TextButtonThemeData(
        style: button(AfTokens.accent, Colors.transparent).copyWith(
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? const BorderSide(color: AfTokens.focus, width: 3)
                : BorderSide.none,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: button(
          AfTokens.accent,
          Colors.transparent,
        ).copyWith(padding: const WidgetStatePropertyAll(EdgeInsets.all(12))),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: AfTokens.surface,
        constraints: const BoxConstraints(minHeight: 48),
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AfTokens.focus, width: 3),
        ),
        errorMaxLines: 8,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AfTokens.surface,
        foregroundColor: AfTokens.text,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AfTokens.surface,
        textStyle: text.labelMedium,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium!.copyWith(
            color: states.contains(WidgetState.disabled)
                ? AfTokens.muted
                : AfTokens.text,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AfTokens.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
