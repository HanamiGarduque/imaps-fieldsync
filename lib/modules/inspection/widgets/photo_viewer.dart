import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/widgets/sensitive_screen.dart';
import '../services/photo_source_resolver.dart';
import '../services/photo_export_service.dart';
import '../../../core/services/db_helper.dart';

/// Renders a photo whether `path` is a local device file path or a remote
/// (Supabase Storage) URL — used anywhere a photo might be either,
/// e.g. a freshly-captured photo (local) vs. one rehydrated for rework
/// (remote URL, see InspectionProvider.hydrateForRework).
bool isRemotePhotoPath(String path) =>
    path.startsWith('http://') || path.startsWith('https://');

class AdaptivePhotoImage extends StatefulWidget {
  final String path;
  final BoxFit fit;
  final String? fallbackPath;
  final PhotoSourceResolver? resolver;
  final Widget Function(BuildContext context)? errorBuilder;

  /// Bounds the decoded bitmap to this pixel width. Use it for grid
  /// thumbnails so a large photo set decodes small bitmaps instead of one
  /// full-resolution frame per cell. Leave null (full resolution) for the
  /// fullscreen viewer.
  final int? cacheWidth;

  const AdaptivePhotoImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.fallbackPath,
    this.resolver,
    this.errorBuilder,
    this.cacheWidth,
  });

  @override
  State<AdaptivePhotoImage> createState() => _AdaptivePhotoImageState();
}

class _AdaptivePhotoImageState extends State<AdaptivePhotoImage> {
  late Future<ResolvedPhoto?> _photo;

  Future<ResolvedPhoto?> _resolve() async {
    try {
      // Local capture remains usable before/offline from Supabase setup.
      if (PhotoSourceResolver.classify(widget.path) ==
              PhotoSourceKind.localFile &&
          File(widget.path).existsSync()) {
        return ResolvedPhoto.local(widget.path);
      }
      return await (widget.resolver ?? inspectionPhotoResolver()).resolve(
        widget.path,
        fallback: widget.fallbackPath,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _photo = _resolve();
  }

  @override
  void didUpdateWidget(covariant AdaptivePhotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.fallbackPath != widget.fallbackPath ||
        oldWidget.resolver != widget.resolver) {
      _photo = _resolve();
    }
  }

  Widget _error() =>
      widget.errorBuilder?.call(context) ?? const _BrokenImageFallback();

  @override
  Widget build(BuildContext context) => FutureBuilder<ResolvedPhoto?>(
    future: _photo,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      final photo = snapshot.data;
      if (photo == null) return _error();
      return photo.localPath != null
          ? Image.file(
              File(photo.localPath!),
              fit: widget.fit,
              cacheWidth: widget.cacheWidth,
              errorBuilder: (_, _, _) => _error(),
            )
          : Image.memory(
              photo.bytes!,
              fit: widget.fit,
              cacheWidth: widget.cacheWidth,
              errorBuilder: (_, _, _) => _error(),
            );
    },
  );
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
  int startIndex, {
  List<Map<String, dynamic>>? photoDetails,
  String? jobId,
}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => FullscreenPhotoViewer(
        photoPaths: photoPaths,
        startIndex: startIndex,
        photoDetails: photoDetails,
        jobId: jobId,
      ),
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

  /// Same-order per-photo metadata (local_photos / field_job_photos shape).
  final List<Map<String, dynamic>>? photoDetails;
  final String? jobId;
  const FullscreenPhotoViewer({
    super.key,
    required this.photoPaths,
    required this.startIndex,
    this.photoDetails,
    this.jobId,
  });

  @override
  State<FullscreenPhotoViewer> createState() => _FullscreenPhotoViewerState();
}

class _FullscreenPhotoViewerState extends State<FullscreenPhotoViewer> {
  late PageController _pageController;
  late int _currentIndex;
  late final String? _inspectorId;
  bool _savingCopy = false;

  @override
  void initState() {
    super.initState();
    _inspectorId = DBHelper.currentInspectorId;
    _currentIndex = widget.startIndex;
    _pageController = PageController(initialPage: widget.startIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _metadata {
    final details = widget.photoDetails;
    if (details == null ||
        _currentIndex < 0 ||
        _currentIndex >= details.length) {
      return null;
    }
    return details[_currentIndex];
  }

  double? get _latitude {
    final value = _metadata?['latitude'] ?? _metadata?['capture_latitude'];
    final latitude = (value as num?)?.toDouble();
    if (latitude == null || !latitude.isFinite || latitude.abs() > 90) {
      return null;
    }
    return latitude;
  }

  double? get _longitude {
    final value = _metadata?['longitude'] ?? _metadata?['capture_longitude'];
    final longitude = (value as num?)?.toDouble();
    if (longitude == null || !longitude.isFinite || longitude.abs() > 180) {
      return null;
    }
    return longitude;
  }

  Future<void> _copyGoogleMapsLocation() async {
    final latitude = _latitude;
    final longitude = _longitude;
    if (latitude == null || longitude == null) return;
    final url =
        'https://maps.google.com/?q=${latitude.toStringAsFixed(6)},'
        '${longitude.toStringAsFixed(6)}';
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Google Maps location copied.')),
    );
  }

  Future<void> _saveCopy() async {
    if (_savingCopy) return;
    setState(() => _savingCopy = true);
    final outcome = await PhotoExportService.saveCopy(
      path: widget.photoPaths[_currentIndex],
      jobId: widget.jobId ?? _metadata?['job_id'] as String?,
      inspectorId: _inspectorId,
    );
    if (!mounted) return;
    setState(() => _savingCopy = false);
    final message = switch (outcome) {
      PhotoCopyOutcome.saved => 'Copy saved. Original inspection evidence is unchanged.',
      PhotoCopyOutcome.cancelled => null,
      PhotoCopyOutcome.unavailable => 'This photo is not available on this device. Save Copy needs a locally saved photo.',
      PhotoCopyOutcome.failed => 'Could not save the copy. Check free space and destination access, then try again. Your original is unchanged; a partial destination may need removing.',
      PhotoCopyOutcome.unauthorized => 'The inspection session or evidence changed. Reopen this inspection before saving a copy.',
      PhotoCopyOutcome.unsupported => 'Save Copy is available in the Android app.',
    };
    if (message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final metadata = _metadata;
    final notes = (metadata?['notes'] as String?)?.trim() ?? '';
    final hasLocation = _latitude != null && _longitude != null;
    return SensitiveScreen(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text('${_currentIndex + 1} / ${widget.photoPaths.length}'),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: PageView.builder(
          physics: _savingCopy ? const NeverScrollableScrollPhysics() : null,
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
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            color: const Color(0xFF0B1220),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (notes.isNotEmpty) ...[
                  Text(
                    notes,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  hasLocation
                      ? 'Camera/verified GPS: '
                            '${_latitude!.toStringAsFixed(6)}, '
                            '${_longitude!.toStringAsFixed(6)}'
                      : 'No reliable GPS location is recorded for this photo.',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _savingCopy ? null : _saveCopy,
                  icon: const Icon(Icons.save_alt_rounded, size: 18),
                  label: Text(_savingCopy ? 'Saving copy…' : 'Save Copy'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white,
                    minimumSize: const Size(48, 48)),
                ),
                TextButton.icon(
                  onPressed: hasLocation ? _copyGoogleMapsLocation : null,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy Google Maps Location'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white30,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
