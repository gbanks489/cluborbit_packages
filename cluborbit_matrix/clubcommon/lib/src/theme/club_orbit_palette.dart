import 'package:flutter/material.dart';

/// The app's colour themes (from the Figma designs: Light, Navy, Black, Purple). Each is a set of
/// named brand colours, attached to the app's ThemeData as a ThemeExtension, so any widget - in
/// the app or the chat packages - reads them with `ClubOrbitPalette.of(context)` and follows the
/// theme the user picked.
///
/// Dark themes draw inputs and cards as white at low opacity over the background (as the designs
/// do), so they stay right on any background colour.
@immutable
class ClubOrbitPalette extends ThemeExtension<ClubOrbitPalette> {
  const ClubOrbitPalette({
    required this.id,
    required this.name,
    required this.brightness,
    required this.accent,
    required this.onAccent,
    required this.background,
    required this.surface,
    required this.input,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.navBar,
    this.accentGradient,
    Color? highlight,
  }) : _highlight = highlight;

  /// Stable id, saved as the user's choice.
  final String id;

  /// Shown in the theme picker.
  final String name;
  final Brightness brightness;

  /// Buttons, highlights, selected items, the logo's wordmark.
  final Color accent;

  /// Text and icons on [accent] (e.g. a button's label).
  final Color onAccent;

  /// Optional gradient for buttons and other accent fills (Purple); when null, use [accent].
  final Gradient? accentGradient;

  /// Page background.
  final Color background;

  /// Cards, sheets, dialogs, tiles.
  final Color surface;

  /// Text field and search bar fill.
  final Color input;

  /// Outlines and dividers.
  final Color border;
  final Color text;
  final Color textMuted;

  /// App bar and bottom navigation bar - the page background, so they blend in.
  final Color navBar;

  final Color? _highlight;

  /// The brand's bright colour for soft highlights (e.g. the user's own chat bubbles, tinted
  /// with it): the accent, except on Light, where the accent is navy and this stays yellow.
  Color get highlight => _highlight ?? accent;

  bool get isDark => brightness == Brightness.dark;

  /// [accentGradient], or a flat one of [accent] - for widgets that always paint a gradient.
  Gradient get accentFill =>
      accentGradient ?? LinearGradient(colors: [accent, accent]);

  // ---- The themes --------------------------------------------------------------------------

  static const Color _yellow = Color(0xFFFBCC07);
  static const Color _navy = Color(0xFF0C1C36);

  /// Today's look (dark navy and yellow) - the default.
  static const ClubOrbitPalette navy = ClubOrbitPalette(
    id: 'navy',
    name: 'Navy',
    brightness: Brightness.dark,
    accent: _yellow,
    onAccent: _navy,
    background: _navy,
    surface: Color(0xFF3D495E),
    input: Color(0xFF1E2942),
    border: Color(0x33FFFFFF),
    text: Colors.white,
    textMuted: Color(0x99FFFFFF),
    navBar: _navy,
  );

  /// Navy turned inside out: white pages with navy as the accent and text (yellow on white is
  /// too faint to read), and yellow on navy for buttons and selected items.
  static const ClubOrbitPalette light = ClubOrbitPalette(
    id: 'light',
    name: 'Light',
    brightness: Brightness.light,
    accent: _navy,
    onAccent: _yellow,
    highlight: _yellow,
    background: Colors.white,
    surface: Color(0xFFEAEEF4),
    input: Colors.white,
    border: Color(0xFFD3DAE5),
    text: _navy,
    textMuted: Color(0x990C1C36),
    navBar: Colors.white,
  );

  static const ClubOrbitPalette black = ClubOrbitPalette(
    id: 'black',
    name: 'Black',
    brightness: Brightness.dark,
    accent: Color(0xFFA4EC40),
    onAccent: Colors.black,
    background: Colors.black,
    surface: Color(0xFF333333),
    input: Color(0xFF191919),
    border: Color(0x33FFFFFF),
    text: Colors.white,
    textMuted: Color(0x99FFFFFF),
    navBar: Colors.black,
  );

  static const ClubOrbitPalette purple = ClubOrbitPalette(
    id: 'purple',
    name: 'Purple',
    brightness: Brightness.dark,
    accent: Color(0xFF7C69C2),
    onAccent: Colors.white,
    accentGradient: LinearGradient(
      colors: [Color(0xFF6569CD), Color(0xFF8F69B9)],
    ),
    background: Color(0xFF171928),
    surface: Color(0xFF454753),
    input: Color(0xFF2E303D),
    border: Color(0x33FFFFFF),
    text: Colors.white,
    textMuted: Color(0x99FFFFFF),
    navBar: Color(0xFF171928),
  );

  /// Deep sea blue with a teal accent.
  static const ClubOrbitPalette ocean = ClubOrbitPalette(
    id: 'ocean',
    name: 'Ocean',
    brightness: Brightness.dark,
    accent: Color(0xFF2EC4B6),
    onAccent: Color(0xFF04222B),
    background: Color(0xFF0A1F2C),
    surface: Color(0xFF1E3A4A),
    input: Color(0xFF13303F),
    border: Color(0x33FFFFFF),
    text: Colors.white,
    textMuted: Color(0x99FFFFFF),
    navBar: Color(0xFF0A1F2C),
  );

  /// Warm cream with a burnt-orange accent (dark enough to read as text on the cream).
  static const ClubOrbitPalette sunrise = ClubOrbitPalette(
    id: 'sunrise',
    name: 'Sunrise',
    brightness: Brightness.light,
    accent: Color(0xFFC2410C),
    onAccent: Colors.white,
    background: Color(0xFFFFFBF5),
    surface: Color(0xFFFBEFE3),
    input: Colors.white,
    border: Color(0xFFEAD9C6),
    text: Color(0xFF2B1D14),
    textMuted: Color(0x992B1D14),
    navBar: Color(0xFFFFFBF5),
  );

  static const List<ClubOrbitPalette> all = [
    navy,
    light,
    black,
    purple,
    ocean,
    sunrise,
  ];

  static const ClubOrbitPalette fallback = navy;

  /// The app's current palette, for code without a BuildContext to look it up (e.g. the chat
  /// packages' PlayerUiSignalTheme colours). Kept in step with the theme by the app.
  static ClubOrbitPalette current = fallback;

  static ClubOrbitPalette byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => fallback);

  /// The palette of the app's current theme (Navy when none is set, e.g. in a test).
  static ClubOrbitPalette of(BuildContext context) =>
      Theme.of(context).extension<ClubOrbitPalette>() ?? fallback;

  // ---- ThemeExtension ----------------------------------------------------------------------

  @override
  ClubOrbitPalette copyWith({
    Color? accent,
    Color? onAccent,
    Color? background,
    Color? surface,
    Color? input,
    Color? border,
    Color? text,
    Color? textMuted,
    Color? navBar,
  }) {
    return ClubOrbitPalette(
      id: id,
      name: name,
      brightness: brightness,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentGradient: accentGradient,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      input: input ?? this.input,
      border: border ?? this.border,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      navBar: navBar ?? this.navBar,
      highlight: _highlight,
    );
  }

  @override
  ClubOrbitPalette lerp(ClubOrbitPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return ClubOrbitPalette(
      id: t < 0.5 ? id : other.id,
      name: t < 0.5 ? name : other.name,
      brightness: t < 0.5 ? brightness : other.brightness,
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      accentGradient: t < 0.5 ? accentGradient : other.accentGradient,
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      input: mix(input, other.input),
      border: mix(border, other.border),
      text: mix(text, other.text),
      textMuted: mix(textMuted, other.textMuted),
      navBar: mix(navBar, other.navBar),
      highlight: mix(highlight, other.highlight),
    );
  }
}
