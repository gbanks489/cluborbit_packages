import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:lottie/lottie.dart';

/// The emojis that have an animated version - Google's Noto Animated Emoji (CC BY 4.0,
/// https://googlefonts.github.io/noto-emoji-animation/), checked to exist on its server. Shown
/// in the picker's Animated tab, and animated wherever they appear on their own.
abstract final class AnimatedEmojis {
  static const List<String> popular = [
    '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃', '😉', '😊', '😇', '🥰', '😍',
    '🤩', '😘', '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔', '🤐', '🤨', '😐',
    '😑', '😶', '😏', '😒', '🙄', '😬', '😌', '😔', '😪', '🤤', '😴', '😷', '🤒', '🤕', '🤢',
    '🤮', '🥵', '🥶', '🥴', '😵', '🤯', '🤠', '🥳', '😎', '🤓', '🧐', '😕', '😟', '🙁', '😮',
    '😯', '😲', '😳', '🥺', '😦', '😧', '😨', '😰', '😥', '😢', '😭', '😱', '😖', '😣', '😞',
    '😓', '😩', '😫', '🥱', '😤', '😡', '😠', '🤬', '😈', '👿', '💀', '💩', '🤡', '👻', '👽',
    '🤖', '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '💔', '💕', '💖', '💗', '💯', '💥',
    '💫', '🔥', '✨', '🎉', '🎊', '🎈', '🎁', '🏆', '🥇', '⚽', '🏀', '🎾', '⚾', '🏓', '🏸',
    '👍', '👎', '👏', '🙌', '👋', '🤝', '🙏', '💪', '👀', '🤞', '✌️', '🤘', '👌', '🫶', '🌟',
    '⭐', '🌈', '⚡', '❄️', '🍕', '🍔', '🍿', '🍻', '🥂', '☕', '🎂', '🐱', '🦄', '🐐', '🚀',
  ];

  static final Set<String> _available = popular.toSet();

  /// [emoji] in the form its animation is listed under, or null when it has none. Accepts it
  /// with or without the U+FE0F variation selector (pickers differ, e.g. ❤ vs ❤️).
  static String? normalize(String emoji) {
    final trimmed = emoji.trim();
    if (_available.contains(trimmed)) return trimmed;
    const variation = '\u{FE0F}';
    final withSelector = '$trimmed$variation';
    if (_available.contains(withSelector)) return withSelector;
    final without = trimmed.replaceAll(variation, '');
    return _available.contains(without) ? without : null;
  }

  static bool has(String emoji) => normalize(emoji) != null;

  /// The animation's address: the emoji's code points in hex, joined with underscores.
  static String lottieUrl(String emoji) {
    final key = emoji.runes.map((r) => r.toRadixString(16)).join('_');
    return 'https://fonts.gstatic.com/s/e/notoemoji/latest/$key/lottie.json';
  }

  // One download per emoji per run; files are kept on disk by the cache manager.
  static final Map<String, Future<File>> _files = {};

  static Future<File> file(String emoji) => _files.putIfAbsent(
    emoji,
    () => DefaultCacheManager().getSingleFile(lottieUrl(emoji)).catchError((
      Object error,
    ) {
      _files.remove(emoji); // Retry next time rather than caching the failure.
      throw error;
    }),
  );
}

/// An emoji drawn with its Noto animation, played [loops] times and then held on its last
/// frame - or, with [animate] false, held still. Emojis without an animation (and any that
/// can't be loaded) are drawn as the normal emoji, so this is safe to use for any emoji.
class AnimatedEmoji extends StatefulWidget {
  const AnimatedEmoji({
    required this.emoji,
    this.size = 32,
    this.loops = 2,
    this.animate = true,
    super.key,
  });

  final String emoji;
  final double size;
  final int loops;
  final bool animate;

  @override
  State<AnimatedEmoji> createState() => _AnimatedEmojiState();
}

class _AnimatedEmojiState extends State<AnimatedEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  Future<File>? _file;
  String? _animated;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AnimatedEmoji oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emoji != widget.emoji) _load();
  }

  void _load() {
    _animated = AnimatedEmojis.normalize(widget.emoji);
    _file = _animated == null ? null : AnimatedEmojis.file(_animated!);
  }

  void _onLoaded(LottieComposition composition) {
    _controller.duration = composition.duration;
    if (!widget.animate) {
      _controller.value = 0;
      return;
    }
    unawaited(_play());
  }

  Future<void> _play() async {
    for (var i = 0; i < widget.loops && mounted; i++) {
      try {
        await _controller.forward(from: 0).orCancel;
      } on TickerCanceled {
        return;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget get _fallback => SizedBox(
    width: widget.size,
    height: widget.size,
    child: Center(
      child: Text(
        widget.emoji,
        style: TextStyle(fontSize: widget.size * 0.8, height: 1),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file == null) return _fallback;
    return FutureBuilder<File>(
      future: file,
      builder: (context, snapshot) {
        final loaded = snapshot.data;
        if (loaded == null) return _fallback;
        return Lottie.file(
          loaded,
          key: ValueKey(loaded.path),
          width: widget.size,
          height: widget.size,
          controller: _controller,
          onLoaded: _onLoaded,
          errorBuilder: (_, _, _) => _fallback,
        );
      },
    );
  }
}

/// A short "pop" of [emoji]'s animation over the screen - e.g. when a reaction is added. Does
/// nothing for emojis without an animation.
void showEmojiBurst(BuildContext context, String emoji) {
  if (!AnimatedEmojis.has(emoji)) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.4, end: 1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: AnimatedEmoji(emoji: emoji, size: 140, loops: 1),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(milliseconds: 1800), () {
    if (entry.mounted) entry.remove();
  });
}
