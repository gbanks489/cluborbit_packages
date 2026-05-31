part of '../chat_screen.dart';

// ---------------------------------------------------------------------------
// _AvatarThumb – circle avatar with online-presence dot and download fallback
// ---------------------------------------------------------------------------

class _AvatarThumb extends StatefulWidget {
  const _AvatarThumb({
    required this.imageUrl,
    required this.initials,
    required this.size,
    required this.backgroundColor,
    this.useGroupPlaceholder = false,
    this.showPresence = false,
    this.isOnline = false,
  });

  final String? imageUrl;
  final String initials;
  final double size;
  final Color backgroundColor;
  final bool useGroupPlaceholder;
  final bool showPresence;
  final bool isOnline;

  @override
  State<_AvatarThumb> createState() => _AvatarThumbState();
}

class _AvatarThumbState extends State<_AvatarThumb> {
  static const Color _groupAvatarBackgroundColor = Color(0xFFE7EAED);
  static const Color _groupAvatarForegroundColor = Color(0xFFADB4BA);

  String? _activeUrl;
  bool _attemptedDownloadFallback = false;

  Widget _defaultAvatarImage() {
    if (widget.useGroupPlaceholder) {
      return CircleAvatar(
        radius: widget.size / 2,
        backgroundColor: _groupAvatarBackgroundColor,
        child: Icon(
          Icons.groups_rounded,
          size: widget.size * 0.54,
          color: _groupAvatarForegroundColor,
        ),
      );
    }
    return ClipOval(
      child: Image.asset(
        'assets/images/blank_profile_pic.png',
        package: 'clubcommon',
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _activeUrl = widget.imageUrl;
  }

  @override
  void didUpdateWidget(covariant _AvatarThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _activeUrl = widget.imageUrl;
      _attemptedDownloadFallback = false;
    }
  }

  String? _downloadFallbackUrl(String? url) {
    if (url == null || url.isEmpty) {
      return null;
    }
    if (!url.contains('/_matrix/media/v3/thumbnail/')) {
      return null;
    }

    var fallback = url.replaceFirst(
      '/_matrix/media/v3/thumbnail/',
      '/_matrix/media/v3/download/',
    );
    final queryIndex = fallback.indexOf('?');
    if (queryIndex >= 0) {
      fallback = fallback.substring(0, queryIndex);
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final url = _activeUrl;
    if (url != null && url.isNotEmpty) {
      final avatar = CircleAvatar(
        radius: widget.size / 2,
        backgroundColor: widget.backgroundColor,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: url,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            memCacheWidth: (widget.size * 3).round(),
            errorWidget: (context, error, _) {
              if (!_attemptedDownloadFallback) {
                final fallback = _downloadFallbackUrl(url);
                if (fallback != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() {
                      _attemptedDownloadFallback = true;
                      _activeUrl = fallback;
                    });
                  });
                  return const SizedBox.shrink();
                }
              }
              return _defaultAvatarImage();
            },
            placeholder: (context, url) => CircleAvatar(
              radius: widget.size / 2,
              backgroundColor: widget.backgroundColor,
              child: Text(
                widget.initials,
                style: TextStyle(
                  fontSize: widget.size * 0.36,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );

      if (!widget.showPresence) return avatar;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: widget.size * 0.32,
              height: widget.size * 0.32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isOnline ? const Color(0xFF44CC77) : Colors.grey,
                border: Border.all(color: Colors.transparent, width: 1.5),
              ),
            ),
          ),
        ],
      );
    }

    // No URL – show initials avatar
    final initialsAvatar = CircleAvatar(
      radius: widget.size / 2,
      backgroundColor: widget.backgroundColor,
      child: Text(
        widget.initials,
        style: TextStyle(
          fontSize: widget.size * 0.36,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    if (!widget.showPresence) return initialsAvatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        initialsAvatar,
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: widget.size * 0.32,
            height: widget.size * 0.32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.isOnline ? const Color(0xFF44CC77) : Colors.grey,
            ),
          ),
        ),
      ],
    );
  }
}
