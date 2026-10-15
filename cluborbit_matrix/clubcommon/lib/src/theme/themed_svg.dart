import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ByteData;
import 'package:flutter_svg/flutter_svg.dart';

import 'club_orbit_palette.dart';

/// The app's SVG icons (assets/icon) are drawn in the Navy theme's yellow. This loads one with
/// that yellow swapped for the colour theme's accent, so icons match the theme (unchanged in
/// Navy and Light, whose accent is that yellow). Use it in place of SvgPicture.asset
/// (pass [package] for icons from another package, e.g. 'clubcommon').
class ThemedSvg {
  ThemedSvg._();

  static SvgPicture asset(
    String assetName, {
    String? package,
    /// Recolours the icon's white parts too (e.g. the white discs behind the profile menu
    /// icons), so they sit on the theme instead of always being white.
    Color? whiteAs,
    double? width,
    double? height,
    ColorFilter? colorFilter,
    @Deprecated('Use colorFilter') Color? color,
  }) {
    final palette = ClubOrbitPalette.current;
    return SvgPicture(
      _BlackFillAssetLoader(
        assetName,
        packageName: package,
        colorMapper: _AccentColorMapper(palette.accent, palette.onAccent, whiteAs),
      ),
      width: width,
      height: height,
      colorFilter: colorFilter ??
          (color == null ? null : ColorFilter.mode(color, BlendMode.srcIn)),
    );
  }
}

/// Gives shapes left at SVG's implicit black fill (the glyphs in the yellow-circle action icons)
/// an explicit black, so they go through the colour mapper like the rest.
class _BlackFillAssetLoader extends SvgAssetLoader {
  const _BlackFillAssetLoader(
    super.assetName, {
    super.packageName,
    super.colorMapper,
  });

  static final RegExp _rootTag = RegExp(r'<svg\b[^>]*>');

  // A shape with no fill of its own (or from the root): SVG draws it black.
  static final RegExp _unfilledShape = RegExp(
    r'<(path|circle|rect|ellipse|polygon)\b(?![^>]*\sfill=)',
  );

  @override
  String provideSvg(ByteData? message) {
    final svg = super.provideSvg(message);
    final root = _rootTag.firstMatch(svg);
    // fill="none" on the root (outline icons) means unfilled shapes really are unfilled.
    if (root == null || root.group(0)!.contains(RegExp(r'\sfill='))) return svg;
    return svg.replaceAllMapped(
      _unfilledShape,
      (m) => '<${m.group(1)} fill="#000000"',
    );
  }
}

class _AccentColorMapper extends ColorMapper {
  const _AccentColorMapper(this.accent, this.onAccent, this.whiteAs);

  final Color accent;

  /// Black in the icons is the glyph drawn on the yellow circle: drawn in the theme's colour
  /// for content on the accent (navy in Navy, yellow on Light's navy, white on Purple).
  final Color onAccent;
  final Color? whiteAs;

  /// The yellows used in the icon files (and the paler golds of a couple of them).
  static const _yellows = {0xFFFBCC07, 0xFFFFCC00, 0xFFFFC000, 0xFFF9DB78, 0xFFEAC452};

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    final opaque = color.withAlpha(255).toARGB32();
    // White (and the light grey some icons use for white) - e.g. the profile icons' discs.
    if (whiteAs != null && (opaque == 0xFFFFFFFF || opaque == 0xFFEBEBEB)) {
      // Keeps the replacement's own transparency (e.g. a fully transparent whiteAs).
      return whiteAs!.withValues(alpha: whiteAs!.a * color.a);
    }
    // Black or navy in the icons is the glyph/badge drawn on the yellow (e.g. ic_next's circle).
    if (opaque == 0xFF000000 || opaque == 0xFF0C1C36) {
      return onAccent.withValues(alpha: onAccent.a * color.a);
    }
    if (!_yellows.contains(opaque)) return color;
    return accent.withValues(alpha: color.a);
  }

  // Part of the picture cache key: icons are cached per accent colour.
  @override
  bool operator ==(Object other) =>
      other is _AccentColorMapper &&
      other.accent == accent &&
      other.onAccent == onAccent &&
      other.whiteAs == whiteAs;

  @override
  int get hashCode => Object.hash(accent, onAccent, whiteAs);
}

/// An icon on a disc in the theme's card colour, in the accent - the profile menu's and the
/// profile page's style. With [color] (e.g. Logout's red) it's an outlined ring in that colour
/// instead, so it stands apart.
class ThemedIconDisc extends StatelessWidget {
  const ThemedIconDisc({required this.child, this.size = 40, this.color, super.key});

  /// One of the icon files with a white disc behind the glyph (ic_email.svg, ...): that disc
  /// is replaced by this one.
  ThemedIconDisc.svg(String assetName, {double size = 40, Color? color, Key? key})
    : this(
        size: size,
        color: color,
        key: key,
        child: ThemedSvg.asset(
          assetName,
          whiteAs: const Color(0x00000000),
          width: size - 4,
          height: size - 4,
          colorFilter: color == null ? null : ColorFilter.mode(color, BlendMode.srcIn),
        ),
      );

  final Widget child;
  final double size;

  /// The ring and glyph colour for an outlined icon; null for the themed disc.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = ClubOrbitPalette.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color == null ? palette.surface : null,
        border: color == null ? null : Border.all(color: color!, width: 2),
      ),
      child: child,
    );
  }
}
