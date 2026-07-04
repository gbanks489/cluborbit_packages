import 'dart:async';

import 'package:flutter/material.dart';
import 'package:clubcommon/clubcommon.dart';

class PlayerUiSearchBar extends StatefulWidget {
  const PlayerUiSearchBar({
    super.key,
    this.controller,
    this.onChanged,
    this.title = 'chats and users',
    this.accentColor = PlayerUiSignalTheme.secondaryColor,
    this.debounceDuration = const Duration(milliseconds: 220),
  });

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String title;
  final Color accentColor;
  final Duration debounceDuration;

  @override
  State<PlayerUiSearchBar> createState() => _PlayerUiSearchBarState();
}

class _PlayerUiSearchBarState extends State<PlayerUiSearchBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _debounceTimer;

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _emitChanged(String value) {
    _debounceTimer?.cancel();
    if (widget.debounceDuration <= Duration.zero) {
      widget.onChanged?.call(value);
      return;
    }
    _debounceTimer = Timer(widget.debounceDuration, () {
      widget.onChanged?.call(value);
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _focusNode = FocusNode();
    _controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.removeListener(_handleControllerChanged);
    if (widget.controller == null) {
      _controller.dispose();
    }
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _emitChanged,
          cursorColor: Colors.white,
          selectionControls: MaterialTextSelectionControls(),
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            prefixIcon: Icon(Icons.search, color: widget.accentColor),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _debounceTimer?.cancel();
                      _controller.clear();
                      widget.onChanged?.call('');
                      setState(() {});
                    },
                    icon: Icon(Icons.clear, color: widget.accentColor),
                  ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: widget.accentColor, width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: widget.accentColor, width: 2),
            ),
            fillColor: Colors.white.withAlpha(16),
            filled: true,
          ),
        ),
        if (_controller.text.isEmpty)
          IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.only(left: 56),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  children: [
                    const TextSpan(
                      text: 'Search ',
                      style: TextStyle(color: Colors.white),
                    ),
                    TextSpan(
                      text: widget.title,
                      style: TextStyle(color: widget.accentColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
