import 'dart:io';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import '../services/location_service.dart';
import '../services/geotag_service.dart';

import '../../tasks/screens/tasks_screen.dart';
import 'inspection_progress.dart';
import 'inspection_checklist_screen.dart';
import 'package:provider/provider.dart';
import '../providers/inspection_provider.dart';
import '../widgets/exit_confirm_dialog.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../../../core/widgets/sensitive_screen.dart';
import '../../../core/theme/insight_theme.dart';
import '../widgets/photo_viewer.dart';
import '../services/photo_source_resolver.dart';
import '../widgets/inspection_step_header.dart';

class CapturePhotoScreen extends StatefulWidget {
  final TaskItem task;
  const CapturePhotoScreen({super.key, required this.task});

  @override
  State<CapturePhotoScreen> createState() => _CapturePhotoScreenState();
}

class _CapturePhotoScreenState extends State<CapturePhotoScreen> {
  static const int maxPhotos = 10;
  final List<Map<String, dynamic>> _capturedPhotos = [];
  bool _isCameraMode = false; 

  final TextEditingController _notesController = TextEditingController();
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;
  Position? _currentPosition;
  String? _capturedPhotoPath;
  bool _isCapturing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _fetchLocation();
    final existingPhotos = context.read<InspectionProvider>().capturedPhotos;
    if (existingPhotos.isNotEmpty) _capturedPhotos.addAll(existingPhotos);
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      _cameraController = CameraController(backCamera, ResolutionPreset.high, enableAudio: false);
      _initializeControllerFuture = _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) { debugPrint('Camera init error: $e'); }
  }

  Future<void> _fetchLocation() async {
    try {
      final position = await LocationService.getCurrentLocation();
      if (mounted) setState(() => _currentPosition = position);
    } catch (e) { debugPrint('Location error: $e'); }
  }

  String _monthName(int month) => const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][month - 1];

  String get _geotagText {
    final now = DateTime.now();
    final dateStr = '${_monthName(now.month)} ${now.day.toString().padLeft(2, '0')}, ${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final coords = _currentPosition != null ? '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}' : 'Locating...';
    return '$dateStr\n$coords';
  }

  Future<void> _capturePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      final xFile = await _cameraController!.takePicture();
      final rawBytes = await xFile.readAsBytes();
      
      // PRESERVED BUSINESS LOGIC: Embed EXIF/Geotag metadata into the image bytes
      final geotaggedBytes = GeotagService.embedGeotag(photoBytes: rawBytes, lines: _geotagText.split('\n'));
      
      final directory = await getApplicationDocumentsDirectory();
      final savedFile = File('${directory.path}/inspection_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await savedFile.writeAsBytes(geotaggedBytes);
      if (mounted) setState(() => _capturedPhotoPath = savedFile.path);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _retakePhoto() => setState(() => _capturedPhotoPath = null);

  void _confirmRemovePhoto(int index) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this photo?'),
        content: const Text('This photo will be removed from the inspection. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _removePhoto(index);
            },
            child: const Text('Remove', style: TextStyle(color: InsightTheme.redInk)),
          ),
        ],
      ),
    );
  }

  Future<void> _removePhoto(int index) async {
    if (index < 0 || index >= _capturedPhotos.length) return;
    final removed = await context.read<InspectionProvider>().removePhoto(index);
    if (!mounted) return;
    if (!removed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This photo is already submitted or could not be removed locally.',
          ),
        ),
      );
      return;
    }
    // Screen-local `_capturedPhotos` and InspectionProvider's own list have
    // been kept in lockstep — appended together in _savePhotoAndReturnToGrid
    // and seeded together in initState — so the same index is safe to
    // remove from both. The provider confirms the file and row cleanup
    // before this grid changes.
    setState(() => _capturedPhotos.removeAt(index));
  }

  void _savePhotoAndReturnToGrid() {
    if (_capturedPhotos.length >= maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Max $maxPhotos photos reached.', style: InsightTheme.inter(13, c: Colors.white)), backgroundColor: InsightTheme.ink));
      setState(() { _isCameraMode = false; _capturedPhotoPath = null; });
      return;
    }
    if (_capturedPhotoPath == null) return;
    context.read<InspectionProvider>().addPhoto(photoPath: _capturedPhotoPath!, photoNotes: _notesController.text, latitude: _currentPosition?.latitude, longitude: _currentPosition?.longitude);
    setState(() {
      _capturedPhotos.add({'photoPath': _capturedPhotoPath, 'notes': _notesController.text, 'latitude': _currentPosition?.latitude, 'longitude': _currentPosition?.longitude, 'capturedAt': DateTime.now().toIso8601String()});
      _isCameraMode = false; _capturedPhotoPath = null; _notesController.clear();
    });
  }

  void _finishAndContinue() {
    if (_capturedPhotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Capture at least one photo.', style: InsightTheme.inter(13, c: Colors.white)), backgroundColor: InsightTheme.ink));
      return;
    }
    InspectionProgress.instance.markStepComplete(3);
    // Issue 4 fix (device-test finding — Task Overview showed "no photos
    // on file" after this step was already finished): saveStepPhotos()
    // used to only run on early exit, the rework-only Save button, or
    // final submit — never on normal forward progress, unlike checklist
    // (which auto-saves per toggle). Fire-and-forget so a slow/offline
    // save can't delay navigation; it now has its own outbox fallback
    // too (see SyncOutboxService.enqueuePhotosUpdate), so nothing is
    // lost either way.
    context.read<InspectionProvider>().saveStepPhotos();
    Navigator.push(context, MaterialPageRoute(builder: (_) => InspectionChecklistScreen(task: widget.task, capturedPhotos: _capturedPhotos)));
  }

  @override
  void dispose() { _notesController.dispose(); _cameraController?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => SensitiveScreen(child: _isCameraMode ? _buildCameraMode() : _buildGridMode());

  Widget _buildGridMode() {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    return PopScope(
      canPop: !context.read<InspectionProvider>().isReworkMode && InspectionProgress.instance.currentStep > 1,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          context.read<InspectionProvider>().saveStepPhotos();
          return;
        }
        handleInspectionExit(
          context,
          onSaveProgress: () => context.read<InspectionProvider>().saveStepPhotos(),
          isReworkMode: context.read<InspectionProvider>().isReworkMode,
        );
      },
      child: Scaffold(
      backgroundColor: InsightTheme.bg,
      body: Stack(
        children: [
          Positioned(top: -60, right: -60, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40), child: Container(width: 260, height: 260, decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withValues(alpha: 0.20))))),
          Positioned(bottom: -80, left: -80, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40), child: Container(width: 220, height: 220, decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withValues(alpha: 0.10))))),

          SafeArea(
            child: Column(
              children: [
                InspectionStepHeader(
                  title: 'Photographic Evidence',
                  subtitle: widget.task.location,
                  stepNumber: 3,
                  stepSubtitle: 'CAPTURE EVIDENCE',
                  onBack: () => handleInspectionExit(
                    context,
                    onSaveProgress: () => context.read<InspectionProvider>().saveStepPhotos(),
                    isReworkMode: context.read<InspectionProvider>().isReworkMode,
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    physics: const BouncingScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1),
                    itemCount: _capturedPhotos.length + (_capturedPhotos.length < maxPhotos ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index < _capturedPhotos.length) {
                        final paths = inspectionDisplayPaths(
                          _capturedPhotos.map((p) => p['photoPath'] as String).toList(),
                          widget.task.id, widget.task.photoDetails, widget.task.photoPaths);
                        return _PhotoCell(
                          photoPath: paths[index],
                          allPhotoPaths: paths,
                          index: index,
                          onRemove: () => _confirmRemovePhoto(index),
                        );
                      }
                      return _AddPhotoCell(onTap: () => setState(() => _isCameraMode = true));
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text('${_capturedPhotos.length} / $maxPhotos photos', style: InsightTheme.jetBrains(10, c: InsightTheme.ink3)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Row(
                    children: [
                      if (context.watch<InspectionProvider>().isReworkMode) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSaving ? null : () async {
                              setState(() => _isSaving = true);
                              final ok = await context.read<InspectionProvider>().saveStepPhotos();
                              if (!mounted) return;
                              setState(() => _isSaving = false);
                              // Issue 2 fix (Completed Category enhancement):
                              // during rework there should be exactly one
                              // button — Save — and it should return to
                              // Inspection Summary, not leave the inspector
                              // stranded on the step screen needing a
                              // separate "Continue" tap that doesn't even
                              // make sense here (there's no next rework step
                              // to continue to).
                              if (ok) {
                                Navigator.pop(context);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Save failed.')));
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: _isSaving
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text('Save', style: InsightTheme.poppins(15, w: FontWeight.w600, c: InsightTheme.blue1)),
                          ),
                        ),
                      ] else ...[
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _finishAndContinue,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ).copyWith(elevation: WidgetStateProperty.all(0)),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [InsightTheme.blue1, InsightTheme.blue2], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: InsightTheme.blue1.withValues(alpha: 0.32), blurRadius: 20, offset: const Offset(0, 8))],
                            ),
                            child: Container(
                              alignment: Alignment.center, constraints: const BoxConstraints(minHeight: 52),
                              child: Text('Continue to Checklist', style: InsightTheme.poppins(15, w: FontWeight.w600, c: Colors.white)),
                            ),
                          ),
                        ),
                      ),
                      ],
                    ],
                  ),
                ),
              ],
          ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildCameraMode() {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final hasCapturedPhoto = _capturedPhotoPath != null;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0B1623), Color(0xFF111D2D), Color(0xFF0D1B2A)],
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final previewHeight = (constraints.maxHeight * (hasCapturedPhoto ? 0.50 : 0.72)).clamp(280.0, 540.0);

                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(bottom: keyboardInset > 0 ? keyboardInset : 18),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                              ),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                                onPressed: () => setState(() { _isCameraMode = false; _capturedPhotoPath = null; }),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Capture Site Photo',
                                style: InsightTheme.poppins(18, w: FontWeight.w700, c: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          width: double.infinity,
                          height: previewHeight,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.32),
                                blurRadius: 28,
                                spreadRadius: 1,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            children: [
                              Positioned.fill(child: _buildCameraPreviewArea()),
                              if (!hasCapturedPhoto)
                                Positioned(
                                  left: 16,
                                  bottom: 18,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.52),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                                    ),
                                    child: Text(
                                      _geotagText,
                                      style: InsightTheme.mono(12, c: Colors.white, ls: 0.08),
                                    ),
                                  ),
                                ),
                              if (hasCapturedPhoto)
                                Positioned(
                                  top: 16,
                                  right: 16,
                                  child: GestureDetector(
                                    onTap: _retakePhoto,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.62),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
                                          const SizedBox(width: 8),
                                          Text('Retake', style: InsightTheme.poppins(13, w: FontWeight.w600, c: Colors.white)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              if (!hasCapturedPhoto)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: 0,
                                  child: Container(
                                    height: 110,
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [Colors.black, Colors.transparent],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (!hasCapturedPhoto)
                        const SizedBox(height: 8),
                      if (hasCapturedPhoto) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE7F3FF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFB9D8FF)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.info_outline_rounded, color: Color(0xFF1F6FEB), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Save the photo evidence before leaving this screen or it will disappear.',
                                    style: InsightTheme.inter(12, c: const Color(0xFF1D4ED8), w: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                          decoration: const BoxDecoration(
                            color: InsightTheme.surface,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Inspection Notes', style: InsightTheme.poppins(17, w: FontWeight.w700, c: InsightTheme.ink)),
                              const SizedBox(height: 14),
                              Container(
                                width: double.infinity,
                                constraints: const BoxConstraints(minHeight: 120, maxHeight: 240),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: InsightTheme.bg,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: InsightTheme.line),
                                ),
                                child: TextField(
                                  controller: _notesController,
                                  keyboardType: TextInputType.multiline,
                                  textInputAction: TextInputAction.newline,
                                  minLines: 4,
                                  maxLines: 8,
                                  style: InsightTheme.inter(14, c: InsightTheme.ink),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'Add field observations here...',
                                    hintStyle: InsightTheme.inter(14, c: InsightTheme.ink3),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _savePhotoAndReturnToGrid,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: InsightTheme.blue1,
                                    padding: const EdgeInsets.symmetric(vertical: 18),
                                    elevation: 0,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                  ),
                                  child: Text('Save Photo', style: InsightTheme.poppins(15, w: FontWeight.w600, c: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreviewArea() {
    if (_capturedPhotoPath != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(_capturedPhotoPath!), fit: BoxFit.cover),
          Positioned(
            top: 16, right: 16,
            child: GestureDetector(
              onTap: _retakePhoto,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.2))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.refresh_rounded, color: Colors.white, size: 16), const SizedBox(width: 8), Text('Retake', style: InsightTheme.poppins(13, w: FontWeight.w600, c: Colors.white))]),
              ),
            ),
          ),
        ],
      );
    }
    if (_cameraController == null || _initializeControllerFuture == null) return const Center(child: ImapsLoadingIndicator(size: 60));
    return FutureBuilder<void>(
      future: _initializeControllerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: ImapsLoadingIndicator(size: 60));
        return Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(_cameraController!),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 26),
                child: GestureDetector(
                  onTap: _capturePhoto,
                  child: Container(
                    width: 78, height: 78,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), color: Colors.white.withValues(alpha: 0.2)),
                    child: Center(child: _isCapturing ? const CircularProgressIndicator(color: Colors.white) : Container(width: 58, height: 58, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PhotoCell extends StatelessWidget {
  final String photoPath;
  final List<String> allPhotoPaths;
  final int index;
  final VoidCallback onRemove;
  const _PhotoCell({
    required this.photoPath,
    required this.allPhotoPaths,
    required this.index,
    required this.onRemove,
  });
  @override
  Widget build(BuildContext context) {
    // Use the same private-storage read contract as the fullscreen viewer.
    return GestureDetector(
      onTap: () => openFullscreenPhotoViewer(context, allPhotoPaths, index),
      child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16), border: Border.all(color: InsightTheme.line),

        boxShadow: const [BoxShadow(color: Color(0x0A141628), blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Stack(
        children: [
          Positioned.fill(child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AdaptivePhotoImage(path: photoPath),
          )),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
                  child: Text('Captured', style: InsightTheme.jetBrains(9, c: Colors.white)),
                ),
              ),
            ),
          ),
          Positioned(
            top: 6, right: 6,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                onRemove();
              },
              child: Container(
                width: 26, height: 26,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _AddPhotoCell extends StatelessWidget {
  final VoidCallback onTap;
  const _AddPhotoCell({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(
        decoration: BoxDecoration(color: InsightTheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: InsightTheme.lineStrong, width: 1.5)),
        child: const Center(child: Icon(Icons.add_a_photo_rounded, color: InsightTheme.ink3, size: 28)),
      ),
    );
  }
}