import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PlayerUiSignalTheme {
  static const Color primaryDarkColor = Color.fromRGBO(249, 204, 11, 1);
  static const Color primaryColor = Color.fromRGBO(0, 149, 246, 1);
  static const Color secondaryColor = Color.fromRGBO(12, 29, 54, 1);
  static const Color mobileSearchColor = Color.fromRGBO(38, 38, 38, 1);
  static const Color mobileBackgroundColor = Color.fromRGBO(12, 29, 54, 1);

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
      appBarTheme: const AppBarTheme(
        backgroundColor: secondaryColor,
        foregroundColor: Colors.white,
      ),
    );

    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: mobileSearchColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
