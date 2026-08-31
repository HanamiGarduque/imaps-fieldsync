import 'dart:io';
import 'package:flutter/material.dart';

/// Renders a photo whether `path` is a local device file path or a remote
/// (Supabase Storage) URL — used anywhere a photo might be either,
/// e.g. a freshly-captured photo (local) vs. one rehydrated for rework
/// (remote URL, see InspectionProvider.hydrateForRework).
bool isRemotePhotoPath(String path) =>
    path.startsWith('http://') || path.startsWith('https://');

class AdaptivePhotoImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  final Widget Function(BuildContext context)? errorBuilder;

  const AdaptivePhotoImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (isRemotePhotoPath(path)) {
      return Image.network(
        path,
        fit: fit,
        errorBuilder: (_, _, _) =>
            errorBuilder?.call(context) ?? const _BrokenImageFallback(),
      );
    }
    return Image.file(
      File(path),
      fit: fit,
      errorBuilder: (_, _, _) =>
          errorBuilder?.call(context) ?? const _BrokenImageFallback(),
    );
  }
}

class _BrokenImageFallback extends StatelessWidget {
  const _BrokenImageFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFEDEFF2),
      child: Icon(Icons.broken_image_outlined, color: Color(0xFF9AA1AC)),
    );
  }
}

/// Opens the fullscreen, pinch-to-zoom photo viewer starting at [startIndex]
/// within [photoPaths]. Shared across every screen that shows task photos —
/// don't duplicate a private copy of this per-screen; import and call this.
void openFullscreenPhotoViewer(
  BuildContext context,
  List<String> photoPaths,
  int startIndex,
) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => FullscreenPhotoViewer(photoPaths: photoPaths, startIndex: startIndex),
      fullscreenDialog: true,
    ),
  );
}

/// Fullscreen, swipeable, pinch-to-zoom photo viewer. Extracted from what
/// used to be a private `_FullscreenPhotoViewer` inside
/// parcel_detail_screen.dart — moved here (and taught to also handle local
/// file paths, not just network URLs) so every screen with task photos
/// (Parcel Detail, Completed report, active Photos step / rework) can open
/// the same viewer instead of each screen needing — or forgetting to add —
/// its own tap handling.
class FullscreenPhotoViewer extends StatefulWidget {
  final List<String> photoPaths;
  final int startIndex;
  const FullscreenPhotoViewer({super.key, required this.photoPaths, required this.startIndex});

  @override
  State<FullscreenPhotoViewer> createState() => _FullscreenPhotoViewerState();
}

class _FullscreenPhotoViewerState extends State<FullscreenPhotoViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.startIndex;
    _pageController = PageController(initialPage: widget.startIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_currentIndex + 1} / ${widget.photoPaths.length}'),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.photoPaths.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (context, i) => InteractiveViewer(
          child: Center(
            child: AdaptivePhotoImage(
              path: widget.photoPaths[i],
              fit: BoxFit.contain,
              errorBuilder: (_) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white38,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}