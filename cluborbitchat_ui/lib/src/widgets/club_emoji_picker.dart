import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:cluborbit_matrix/cluborbit_matrix.dart';

import 'animated_emoji.dart';

/// The one emoji picker in chat, for the message composer and for reactions alike: an
/// Animated tab of popular animated emojis (Noto) first, then every emoji (emoji_picker_flutter).
///
/// With [textController], picked emojis are typed into it at the cursor (the composer);
/// without, they're only reported through [onEmojiSelected] (reactions).
class ClubEmojiPicker extends StatefulWidget {
  const ClubEmojiPicker({
    required this.onEmojiSelected,
    this.textController,
    this.onBackspacePressed,
    super.key,
  });

  final ValueChanged<String> onEmojiSelected;
  final TextEditingController? textController;
  final VoidCallback? onBackspacePressed;

  @override
  State<ClubEmojiPicker> createState() => _ClubEmojiPickerState();
}

class _ClubEmojiPickerState extends State<ClubEmojiPicker> {
  // The tab last used, kept for the rest of the session.
  static int _lastTab = 0;
  late int _tab = _lastTab;
  String? _playing;

  void _pickAnimated(String emoji) {
    final controller = widget.textController;
    if (controller != null) {
      final text = controller.text;
      final selection = controller.selection;
      final start = selection.isValid ? selection.start : text.length;
      final end = selection.isValid ? selection.end : text.length;
      controller.value = TextEditingValue(
        text: text.replaceRange(start, end, emoji),
        selection: TextSelection.collapsed(offset: start + emoji.length),
      );
    }
    setState(() => _playing = emoji);
    widget.onEmojiSelected(emoji);
  }

  Widget _tabButton(int index, IconData icon, String label) {
    final selected = _tab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = _lastTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected
                    ? PlayerUiSignalTheme.primaryDarkColor
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? PlayerUiSignalTheme.primaryDarkColor
                    : Colors.white60,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? PlayerUiSignalTheme.primaryDarkColor
                      : Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimated() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 52,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: AnimatedEmojis.popular.length,
      itemBuilder: (context, index) {
        final emoji = AnimatedEmojis.popular[index];
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _pickAnimated(emoji),
          child: Center(
            // Still until picked, then it plays once - a grid of them all moving is too busy.
            child: AnimatedEmoji(
              key: ValueKey('$emoji-${_playing == emoji}'),
              emoji: emoji,
              size: 36,
              loops: 1,
              animate: _playing == emoji,
            ),
          ),
        );
      },
    );
  }

  Widget _buildAll() {
    return EmojiPicker(
      textEditingController: widget.textController,
      onEmojiSelected: (category, emoji) => widget.onEmojiSelected(emoji.emoji),
      onBackspacePressed: widget.onBackspacePressed,
      config: const Config(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            _tabButton(0, Icons.auto_awesome, 'Animated'),
            _tabButton(1, Icons.emoji_emotions_outlined, 'All'),
          ],
        ),
        Expanded(child: _tab == 0 ? _buildAnimated() : _buildAll()),
      ],
    );
  }
}
