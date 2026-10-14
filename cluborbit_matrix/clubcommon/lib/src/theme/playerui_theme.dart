import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'club_orbit_palette.dart';

/// The chat packages' colours. They follow the app's colour theme (ClubOrbitPalette.current,
/// kept up to date by the app), so they're getters, not constants - use them outside `const`.
class PlayerUiSignalTheme {
  static ClubOrbitPalette get _palette => ClubOrbitPalette.current;

  /// The accent: buttons, highlights, selected items (yellow in Navy).
  static Color get primaryDarkColor => _palette.accent;

  /// Text and icons drawn on [primaryDarkColor] (e.g. a yellow button's label).
  static Color get onAccent => _palette.onAccent;

  static const Color primaryColor = Color.fromRGBO(0, 149, 246, 1);

  /// The page background (navy in Navy) - sheets, panels, avatar backgrounds.
  static Color get secondaryColor => _palette.background;

  /// Text field / search fill.
  static Color get mobileSearchColor => _palette.input;

  static Color get mobileBackgroundColor => _palette.background;

  /// Cards, popup menus, dialogs.
  static Color get surface => _palette.surface;

  /// Main and secondary text / icon colours on the page background.
  static Color get text => _palette.text;
  static Color get textMuted => _palette.textMuted;

  static Color get border => _palette.border;

  static bool get isDark => _palette.isDark;

  static ThemeData darkTheme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        brightness: Brightness.dark,
        seedColor: secondaryColor,
        primary: primaryColor,
      ),
      scaffoldBackgroundColor: mobileBackgroundColor,
      appBarTheme: AppBarTheme(
        backgroundColor: secondaryColor,
        foregroundColor: Colors.white,
      ),
    );

    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: mobileSearchColor,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
