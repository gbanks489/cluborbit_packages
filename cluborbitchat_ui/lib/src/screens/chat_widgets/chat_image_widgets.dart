part of '../chat_screen.dart';

// ---------------------------------------------------------------------------
// Encrypted media — a message's attachment may be AES-256-CTR encrypted (see
// cluborbit_matrix's rust/src/attachment_crypto.rs / MatrixRestService.resolveMediaBytes), in
// which case its `mediaUrl`/`thumbnailUrl` point at ciphertext that must be downloaded and
// decrypted before it's displayable — never handed straight to an HTTP-fetching widget like
// CachedNetworkImage. `_MediaRef` bundles a URL with its (possibly absent, for a legacy
// unencrypted message) encryption info; `_resolveMedia` is the one place that downloads+decrypts,
// with a small in-memory cache so re-rendering the same image doesn't repeat the work. Decrypted
// bytes are kept in memory only, never written to disk — the media repo never sees plaintext, and
// neither should the device's disk cache.
// ---------------------------------------------------------------------------

class _MediaRef {
  const _MediaRef({required this.url, this.encryption});

  final String url;
  final Map<String, dynamic>? encryption;

  static _MediaRef? fromUrl(String? url, Map<String, dynamic>? encryption) {
    if (url == null || url.trim().isEmpty) return null;
    return _MediaRef(url: url.trim(), encryption: encryption);
  }
}

final Map<String, Uint8List> _decryptedMediaCache = <String, Uint8List>{};

Future<Uint8List> _resolveMedia(
  ChatController controller,
  _MediaRef media,
) async {
  final cached = _decryptedMediaCache[media.url];
  if (cached != null) return cached;
  final bytes = await controller.resolveMediaBytes(
    media.url,
    encryption: media.encryption,
  );
  // Bounded, not unlimited — a long chat session viewing many photos shouldn't let this grow
  // forever; simplest possible cap rather than a real LRU, since chat media is typically viewed
  // in a burst (scrolling through a room) rather than needing long-term retention.
  if (_decryptedMediaCache.length > 200) _decryptedMediaCache.clear();
  _decryptedMediaCache[media.url] = bytes;
  return bytes;
}

/// Drop-in replacement for `CachedNetworkImage` that downloads+decrypts via `_resolveMedia`
/// instead of fetching `imageUrl` directly — every in-app image render (message bubbles, reply
/// previews, the full-screen viewer) should use this, not `CachedNetworkImage`, since any of them
/// may need to display an encrypted attachment.
class _EncryptedImage extends StatefulWidget {
  const _EncryptedImage({
    required this.media,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  final _MediaRef media;
  final BoxFit fit;
  final Widget Function(BuildContext context)? placeholder;
  final Widget Function(BuildContext context, Object error)? errorWidget;

  @override
  State<_EncryptedImage> createState() => _EncryptedImageState();
}

class _EncryptedImageState extends State<_EncryptedImage> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _EncryptedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.url != widget.media.url) {
      _future = _load();
    }
  }

  Future<Uint8List> _load() {
    final controller = context.read<ChatController>();
    return _resolveMedia(controller, widget.media);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.errorWidget?.call(context, snapshot.error!) ??
              Container(
                color: Colors.black26,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image, color: Colors.white70),
              );
        }
        if (!snapshot.hasData) {
          return widget.placeholder?.call(context) ??
              Container(
                color: Colors.black26,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(strokeWidth: 1.6),
              );
        }
        return Image.memory(
          snapshot.data!,
          fit: widget.fit,
          gaplessPlayback: true,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// _ImageCollageGrid – 1–4 image collage shown in place of a message bubble
// ---------------------------------------------------------------------------

/// A multi-image message as one collage, like WhatsApp: a single rounded frame with thin white
/// lines between the images. 1 image fills it; 2 sit side by side; 3 are one wide on top and two
/// below; 4 or more are a 2x2 grid with "+N" on the fourth for the rest (same as cluborbit-web).
class _ImageCollageGrid extends StatelessWidget {
  const _ImageCollageGrid({required this.images, required this.onOpenAt});

  final List<_MediaRef> images;
  final ValueChanged<int> onOpenAt;

  static const double _line = 2; // the white grid lines
  static const double _radius = 12;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return const SizedBox.shrink();
    }

    // A single image keeps its own aspect ratio (scaled down to fit, never cropped) - an unsized
    // Image preserves its ratio within these bounds. Only the loading/error box is a fixed size.
    if (images.length == 1) {
      Widget box(Widget child) =>
          SizedBox(height: 190, width: double.infinity, child: child);
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: GestureDetector(
            onTap: () => onOpenAt(0),
            child: _EncryptedImage(
              media: images[0],
              fit: BoxFit.contain,
              placeholder: (_) => box(
                Container(
                  color: Colors.black26,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(strokeWidth: 1.6),
                ),
              ),
              errorWidget: (_, _) => box(
                Container(
                  color: Colors.black26,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image, color: Colors.white70),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 240.0;
        final half = (width - _line) / 2;

        Widget grid;
        if (images.length == 2) {
          grid = Row(
            children: [
              SizedBox(width: half, height: half * 1.2, child: _tile(0)),
              _gridLine(width: _line, height: half * 1.2),
              SizedBox(width: half, height: half * 1.2, child: _tile(1)),
            ],
          );
        } else if (images.length == 3) {
          grid = Column(
            children: [
              SizedBox(width: width, height: half, child: _tile(0)),
              _gridLine(width: width, height: _line),
              Row(
                children: [
                  SizedBox(width: half, height: half * 0.75, child: _tile(1)),
                  _gridLine(width: _line, height: half * 0.75),
                  SizedBox(width: half, height: half * 0.75, child: _tile(2)),
                ],
              ),
            ],
          );
        } else {
          final overflowCount = images.length - 4;
          Widget row(int first) => Row(
            children: [
              SizedBox(width: half, height: half, child: _tile(first)),
              _gridLine(width: _line, height: half),
              SizedBox(
                width: half,
                height: half,
                child: _tile(
                  first + 1,
                  overflowCount: first + 1 == 3 ? overflowCount : 0,
                ),
              ),
            ],
          );
          grid = Column(
            children: [
              row(0),
              _gridLine(width: width, height: _line),
              row(2),
            ],
          );
        }

        // No backdrop behind the tiles, so transparent images show the chat background; the
        // white grid lines are drawn explicitly between them.
        return ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: grid,
        );
      },
    );
  }

  static Widget _gridLine({required double width, required double height}) =>
      SizedBox(
        width: width,
        height: height,
        child: const ColoredBox(color: Colors.white),
      );

  Widget _tile(int index, {int overflowCount = 0}) {
    return GestureDetector(
      onTap: () => onOpenAt(index),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _EncryptedImage(media: images[index], fit: BoxFit.cover),
          if (overflowCount > 0)
            Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: Text(
                '+$overflowCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ImageSlideshowScreen – full-screen image viewer with swipe & zoom
// ---------------------------------------------------------------------------

class _ImageSlideshowScreen extends StatefulWidget {
  const _ImageSlideshowScreen({
    required this.images,
    required this.initialIndex,
  });

  final List<_MediaRef> images;
  final int initialIndex;

  @override
  State<_ImageSlideshowScreen> createState() => _ImageSlideshowScreenState();
}

class _ImageSlideshowScreenState extends State<_ImageSlideshowScreen> {
  late final PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.images.length - 1);
    _controller = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} / ${widget.images.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.images.length,
        onPageChanged: (value) {
          setState(() {
            _currentIndex = value;
          });
        },
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: _EncryptedImage(
                media: widget.images[index],
                fit: BoxFit.contain,
                placeholder: (context) => const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
                errorWidget: (context, error) => const Icon(
                  Icons.broken_image,
                  color: Colors.white70,
                  size: 42,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ImageBatchComposerSheet – caption + preview sheet before sending images
// ---------------------------------------------------------------------------

class _ImageBatchComposerSheet extends StatefulWidget {
  const _ImageBatchComposerSheet({
    required this.images,
    required this.initialCaption,
    required this.sendColor,
    required this.fontFamily,
    this.videoPath,
  });

  final List<PickedImageMedia> images;
  final String initialCaption;

  /// A camera video to preview instead of [images].
  final String? videoPath;

  /// The user's bubble colour and message font, so the caption row matches the chat composer.
  final Color sendColor;
  final String fontFamily;

  @override
  State<_ImageBatchComposerSheet> createState() =>
      _ImageBatchComposerSheetState();
}

class _ImageBatchComposerSheetState extends State<_ImageBatchComposerSheet> {
  late final TextEditingController _captionController;
  final FocusNode _captionFocusNode = FocusNode();
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.initialCaption);
    _captionFocusNode.addListener(() => setState(() {}));
    final videoPath = widget.videoPath;
    if (videoPath != null) {
      final controller = VideoPlayerController.file(File(videoPath));
      _videoController = controller;
      controller
        ..setLooping(true)
        ..addListener(() {
          if (mounted) setState(() {});
        })
        ..initialize().then((_) {
          if (mounted) setState(() {});
        });
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _captionFocusNode.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Widget _buildVideoPreview(VideoPlayerController controller) {
    final ready = controller.value.isInitialized;
    return GestureDetector(
      onTap: !ready
          ? null
          : () => controller.value.isPlaying
                ? controller.pause()
                : controller.play(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: !ready
              ? const CircularProgressIndicator(strokeWidth: 2)
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                    if (!controller.value.isPlaying)
                      const Icon(
                        Icons.play_circle_fill_rounded,
                        size: 52,
                        color: Colors.white70,
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  /// The caption box and send button, styled exactly like the chat screen's message composer.
  Widget _buildCaptionRow() {
    final focused = _captionFocusNode.hasFocus;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            constraints: const BoxConstraints(
              minHeight: _ComposerIconButton.size,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: focused
                    ? const Color(0xFF38BDF8).withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: TextField(
              controller: _captionController,
              focusNode: _captionFocusNode,
              minLines: 1,
              maxLines: 5,
              textAlignVertical: TextAlignVertical.center,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              cursorColor: const Color(0xFF38BDF8),
              style: TextStyle(
                fontFamily: widget.fontFamily,
                fontSize: 14,
                height: 1.35,
                color: const Color(0xFFF1F5F9),
              ),
              decoration: InputDecoration(
                hintText: 'Add a caption...',
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                hintStyle: TextStyle(
                  fontFamily: widget.fontFamily,
                  fontSize: 14,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _ComposerIconButton(
          icon: Icons.send_rounded,
          fillColor: widget.sendColor,
          iconColor: Colors.white,
          onPressed: () => Navigator.of(context).pop(_captionController.text),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: PlayerUiSignalTheme.secondaryColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        padding: EdgeInsets.fromLTRB(
          12,
          12,
          12,
          12 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _videoController != null
                    ? 'Video'
                    : 'Selected images (${widget.images.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: _videoController != null ? 240 : 170,
              child: _videoController != null
                  ? _buildVideoPreview(_videoController!)
                  : GridView.builder(
                      scrollDirection: Axis.horizontal,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 1,
                            mainAxisSpacing: 8,
                            childAspectRatio: 1,
                          ),
                      itemCount: widget.images.length,
                      itemBuilder: (context, index) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            widget.images[index].bytes,
                            fit: BoxFit.cover,
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            _buildCaptionRow(),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _VideoPlayerScreen – full-screen video playback. The video is downloaded (and decrypted, if
// encrypted) and played from a temp file — video_player can't read from memory — which is deleted
// when the screen closes.
// ---------------------------------------------------------------------------

class _VideoPlayerScreen extends StatefulWidget {
  const _VideoPlayerScreen({required this.media, required this.title});

  final _MediaRef media;
  final String title;

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  VideoPlayerController? _controller;
  File? _tempFile;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // Always go through the app's authenticated download (and decryption, when the attachment
      // is encrypted) — the media URL may need auth headers a plain network player wouldn't send.
      // Deliberately bypasses _resolveMedia's image cache: videos are large.
      final bytes = await context.read<ChatController>().resolveMediaBytes(
        widget.media.url,
        encryption: widget.media.encryption,
      );
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/chat_video_${DateTime.now().microsecondsSinceEpoch}.mp4',
      );
      await file.writeAsBytes(bytes, flush: true);
      _tempFile = file;
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(() {
        if (mounted) setState(() {});
      });
      setState(() => _controller = controller);
      await controller.play();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    final file = _tempFile;
    if (file != null) {
      unawaited(file.delete().catchError((_) => file));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: Center(
        child: _error != null
            ? const Text(
                'Could not play this video',
                style: TextStyle(color: Colors.white70),
              )
            : controller == null
            ? const CircularProgressIndicator()
            : GestureDetector(
                onTap: () => controller.value.isPlaying
                    ? controller.pause()
                    : controller.play(),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                    if (!controller.value.isPlaying)
                      const Icon(
                        Icons.play_circle_fill,
                        color: Colors.white70,
                        size: 72,
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
