part of '../chat_screen.dart';

// ---------------------------------------------------------------------------
// _ImageCollageGrid – 1–4 image collage shown inside a message bubble
// ---------------------------------------------------------------------------

class _ImageCollageGrid extends StatelessWidget {
  const _ImageCollageGrid({required this.imageUrls, required this.onOpenAt});

  final List<String> imageUrls;
  final ValueChanged<int> onOpenAt;

  @override
  Widget build(BuildContext context) {
    if (imageUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    final displayCount = imageUrls.length > 4 ? 4 : imageUrls.length;
    if (displayCount == 1) {
      return _imageTile(
        context: context,
        imageUrl: imageUrls.first,
        index: 0,
        height: 190,
        hasOverlay: false,
        overflowCount: 0,
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: displayCount,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemBuilder: (context, index) {
        final overflowCount = imageUrls.length - 4;
        final hasOverlay = index == 3 && overflowCount > 0;
        return _imageTile(
          context: context,
          imageUrl: imageUrls[index],
          index: index,
          hasOverlay: hasOverlay,
          overflowCount: overflowCount,
        );
      },
    );
  }

  Widget _imageTile({
    required BuildContext context,
    required String imageUrl,
    required int index,
    double? height,
    required bool hasOverlay,
    required int overflowCount,
  }) {
    final tile = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            placeholder: (context, _) => Container(
              color: Colors.black26,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(strokeWidth: 1.6),
            ),
            errorWidget: (context, error, stackTrace) => Container(
              color: Colors.black26,
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image, color: Colors.white70),
            ),
          ),
          if (hasOverlay)
            Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: Text(
                '+$overflowCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );

    final wrapped = GestureDetector(onTap: () => onOpenAt(index), child: tile);

    if (height != null) {
      return SizedBox(height: height, width: double.infinity, child: wrapped);
    }
    return wrapped;
  }
}

// ---------------------------------------------------------------------------
// _ImageSlideshowScreen – full-screen image viewer with swipe & zoom
// ---------------------------------------------------------------------------

class _ImageSlideshowScreen extends StatefulWidget {
  const _ImageSlideshowScreen({
    required this.imageUrls,
    required this.initialIndex,
  });

  final List<String> imageUrls;
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
    _currentIndex = widget.initialIndex.clamp(0, widget.imageUrls.length - 1);
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
          '${_currentIndex + 1} / ${widget.imageUrls.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.imageUrls.length,
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
              child: CachedNetworkImage(
                imageUrl: widget.imageUrls[index],
                fit: BoxFit.contain,
                placeholder: (context, _) => const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
                errorWidget: (context, error, stackTrace) => const Icon(
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
  });

  final List<PickedImageMedia> images;
  final String initialCaption;

  @override
  State<_ImageBatchComposerSheet> createState() =>
      _ImageBatchComposerSheetState();
}

class _ImageBatchComposerSheetState extends State<_ImageBatchComposerSheet> {
  late final TextEditingController _captionController;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.initialCaption);
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
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
                'Selected images (${widget.images.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 170,
              child: GridView.builder(
                scrollDirection: Axis.horizontal,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
            const SizedBox(height: 4),
            Container(
              decoration: BoxDecoration(
                color: PlayerUiSignalTheme.mobileBackgroundColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: PlayerUiSignalTheme.primaryDarkColor.withAlpha(170),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: CommonWidgets.commonTextFieldForLoginSignUP(
                      context: context,
                      controller: _captionController,
                      hintText: 'Type caption (optional)',
                      minLines: 1,
                      maxLines: 3,
                      filled: false,
                      wantBorder: false,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontFamily: 'Poppins',
                      ),
                      hintStyle: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontFamily: 'Poppins',
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_captionController.text),
                    icon: const Icon(
                      Icons.send,
                      color: PlayerUiSignalTheme.primaryDarkColor,
                    ),
                  ),
                ],
              ),
            ),
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
