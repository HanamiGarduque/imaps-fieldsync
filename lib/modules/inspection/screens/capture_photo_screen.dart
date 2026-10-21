import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/field_form_widgets.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/db_helper.dart';
import '../services/location_service.dart';
import '../services/geotag_service.dart';
import '../services/site_route_guidance.dart';
import '../services/site_location_reference_service.dart';

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
import '../services/pending_capture_store.dart';
import '../widgets/inspection_step_header.dart';

class CapturePhotoScreen extends StatefulWidget {
  final TaskItem task;
  const CapturePhotoScreen({super.key, required this.task});

  @override
  State<CapturePhotoScreen> createState() => _CapturePhotoScreenState();
}

class _CapturePhotoScreenState extends State<CapturePhotoScreen> {
  static const int maxPhotos = 10;
  late final InspectionProvider _provider;
  late final String? _inspectorId;
  bool get _sameInspection =>
      mounted &&
      _inspectorId != null &&
      DBHelper.currentInspectorId == _inspectorId &&
      _provider.activeTask?.id == widget.task.id &&
      _provider.activeTask?.inspectionRoundNumber ==
          widget.task.inspectionRoundNumber;
  int get _round => widget.task.inspectionRoundNumber ?? 0;
  List<Map<String, dynamic>> get _capturedPhotos =>
      _sameInspection ? _provider.capturedPhotos : [];
  bool _isCameraMode = false;

  final TextEditingController _notesController = TextEditingController();
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;
  String? _cameraError;
  Position? _currentPosition;
  String? _capturedPhotoPath;
  Position? _capturedPosition;
  DateTime? _capturedAt;
  String? _pendingPhotoId;
  Map<String, dynamic>? _pendingReference;
  Future<void>? _referenceFuture;
  bool _isCapturing = false;
  bool _isSaving = false;
  bool _isSavingPhoto = false;
  bool _referenceEnsuring = false;
  String? _referenceError;

  @override
  void initState() {
    super.initState();
    _provider = context.read<InspectionProvider>();
    _inspectorId = DBHelper.currentInspectorId;
    _initCamera();
    _fetchLocation();
    unawaited(_cleanAbandonedCaptures());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _referenceFuture = _ensureLocationReference();
    });
  }

  /// Bounded to this owner/job/round; never touches accepted, queued, other
  /// round, other owner or unprovable files.
  Future<void> _cleanAbandonedCaptures() async {
    if (_inspectorId == null || !_sameInspection) return;
    try {
      await PendingCaptureStore.cleanupAbandoned(
        owner: _inspectorId,
        jobId: widget.task.id,
        round: _round,
        protectedPaths: {?_capturedPhotoPath},
      );
    } catch (e) {
      debugPrint('Pending capture cleanup skipped: $e');
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _initializeControllerFuture = _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) {
        setState(() {
          _cameraError =
              'Camera unavailable. Allow camera access for FieldSync in your '
              'device settings, then try again, or add a photo from the gallery.';
        });
      }
    }
  }

  Widget _cameraUnavailable() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              size: 40,
              color: InsightTheme.ink3,
            ),
            const SizedBox(height: 12),
            Text(
              _cameraError ??
                  'Camera unavailable. Allow camera access for FieldSync in '
                      'your device settings, then try again, or add a photo '
                      'from the gallery.',
              textAlign: TextAlign.center,
              style: InsightTheme.openSans(13, c: InsightTheme.ink2, h: 1.4),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                setState(() => _isCameraMode = false);
              },
              child: const Text('Use gallery instead'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchLocation() async {
    try {
      final position = await LocationService.getCurrentLocation(
        timeout: const Duration(seconds: 10),
      );
      if (mounted) setState(() => _currentPosition = position);
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  bool _isReliableCaptureFix(Position position, {DateTime? capturedAt}) {
    if (!position.latitude.isFinite ||
        !position.longitude.isFinite ||
        position.latitude.abs() > 90 ||
        position.longitude.abs() > 180) {
      return false;
    }
    return reliableSiteFix(
      accuracyMeters: position.accuracy,
      timestamp: position.timestamp,
      now: capturedAt ?? DateTime.now(),
    );
  }

  /// Shutter-time fix. A fresh bounded request is preferred; the screen's
  /// earlier fix is reused only while it still passes the same ≤25 m / ≤15 s
  /// gate. There is deliberately no fallback to Step 2 or the parcel point.
  Future<Position?> _acquireShutterFix(DateTime capturedAt) async {
    try {
      final fresh = await LocationService.getCurrentLocation(
        timeout: const Duration(seconds: 8),
      );
      if (_isReliableCaptureFix(fresh, capturedAt: capturedAt)) return fresh;
    } catch (e) {
      debugPrint('Shutter GPS error: $e');
    }
    final cached = _currentPosition;
    if (cached != null && _isReliableCaptureFix(cached, capturedAt: capturedAt)) {
      return cached;
    }
    return null;
  }

  List<String> get _previewFooterLines {
    final position =
        _currentPosition != null && _isReliableCaptureFix(_currentPosition!)
        ? _currentPosition
        : null;
    return GeotagService.captureFooterLines(
      applicant: widget.task.name,
      address: widget.task.locationAddress,
      capturedAt: DateTime.now(),
      latitude: position?.latitude,
      longitude: position?.longitude,
      accuracyMeters: position?.accuracy,
    );
  }

  Future<void> _capturePhoto() async {
    if (!_sameInspection ||
        _isSavingPhoto ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isCapturing) {
      return;
    }
    setState(() => _isCapturing = true);
    final capturedAt = DateTime.now();
    try {
      // Start the shutter-time fix alongside the capture so a weak GPS lock
      // cannot freeze the camera UI. The result is gated; a parcel point or
      // Step 2 verification is never substituted here.
      final fixFuture = _acquireShutterFix(capturedAt);
      final xFile = await _cameraController!.takePicture();
      final rawBytes = await xFile.readAsBytes();
      final position = await fixFuture;

      final geotaggedBytes = await GeotagService.appendFooter(
        photoBytes: rawBytes,
        lines: GeotagService.captureFooterLines(
          applicant: widget.task.name,
          address: widget.task.locationAddress,
          capturedAt: capturedAt,
          latitude: position?.latitude,
          longitude: position?.longitude,
          accuracyMeters: position?.accuracy,
        ),
      );

      if (!_sameInspection) return;
      final photoId = _pendingPhotoId ?? const Uuid().v4();
      final stagedPath = await PendingCaptureStore.stage(
        owner: _inspectorId!,
        jobId: widget.task.id,
        round: _round,
        id: photoId,
        bytes: geotaggedBytes,
      );
      if (_sameInspection) {
        setState(() {
          _capturedPhotoPath = stagedPath;
          _capturedPosition = position;
          _capturedAt = capturedAt;
          _pendingPhotoId = photoId;
        });
      } else {
        await PendingCaptureStore.discard(stagedPath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _discardPendingCapture() {
    if (_isSavingPhoto || _isCapturing) return;
    final path = _capturedPhotoPath;
    _capturedPhotoPath = null;
    _capturedPosition = null;
    _capturedAt = null;
    _pendingPhotoId = null;
    if (path != null) unawaited(_deleteQuietly(path));
  }

  Future<void> _deleteQuietly(String path) async {
    await PendingCaptureStore.discard(path);
  }

  void _retakePhoto() {
    if (_isSavingPhoto || _isCapturing) return;
    _discardPendingCapture();
    setState(() {});
  }

  void _confirmRemovePhoto(int index) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this photo?'),
        content: const Text(
          'This photo will be removed from the inspection. This cannot be undone.',
        ),
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
            child: const Text(
              'Remove',
              style: TextStyle(color: InsightTheme.redInk),
            ),
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
    // The provider is the only evidence list; it removes the row/file first.
    setState(() {});
  }

  Future<void> _savePhotoAndReturnToGrid() async {
    if (_isSavingPhoto || !_sameInspection) return;
    final realCount = _capturedPhotos
        .where((photo) => !isLocationReferencePhoto(photo))
        .length;
    if (realCount >= maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Max $maxPhotos site photos reached.',
            style: InsightTheme.inter(13, c: Colors.white),
          ),
          backgroundColor: InsightTheme.ink,
        ),
      );
      setState(() {
        _isCameraMode = false;
        _discardPendingCapture();
      });
      return;
    }
    final capturedPath = _capturedPhotoPath;
    if (capturedPath == null) return;

    setState(() => _isSavingPhoto = true);
    final capturedAt = _capturedAt ?? DateTime.now();
    final photoId = _pendingPhotoId ??= const Uuid().v4();
    String? acceptedPath;
    try {
      // Durable "acceptance started" first: a crash after this point must
      // leave the staged bytes for a human, never for automatic deletion.
      await PendingCaptureStore.markAccepting(capturedPath);
      if (!_sameInspection) throw StateError('The active inspection changed');
      final directory = await _evidenceDirectory();
      acceptedPath =
          '${directory.path}/inspection_${capturedAt.millisecondsSinceEpoch}.jpg';
      final accepted = File(acceptedPath);
      if (!accepted.existsSync()) {
        File(capturedPath).copySync(acceptedPath);
      }
      final photo = <String, dynamic>{
        'id': photoId,
        'photoPath': acceptedPath,
        'notes': _notesController.text,
        'latitude': _capturedPosition?.latitude,
        'longitude': _capturedPosition?.longitude,
        'capturedAt': GeotagService.storageTimestamp(capturedAt),
      };
      if (!await _provider.persistPhoto(
        photo,
        task: widget.task,
        inspectorId: _inspectorId!,
      )) {
        throw StateError('Photo could not be saved');
      }
      // SQLite, not this preview, now owns the image's lifetime.
      _capturedPhotoPath = null;
      _capturedPosition = null;
      _capturedAt = null;
      _pendingPhotoId = null;
      unawaited(_deleteQuietly(capturedPath));
      if (!_sameInspection) return;
      setState(() {
        _isCameraMode = false;
        _notesController.clear();
      });
    } catch (e) {
      if (acceptedPath != null) {
        await _discardUnacceptedCopy(acceptedPath, photoId);
      }
      if (!mounted || !_sameInspection) {
        // A write may have completed for the initiating task before context
        // changed. Never delete that task's durable image on screen disposal.
        _capturedPhotoPath = null;
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Photo was not saved on this device. The preview is retained; '
            'tap Save Photo to retry before leaving.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSavingPhoto = false);
    }
  }

  /// Removes a just-copied canonical file only when no local row references
  /// its id, so a failed save can be retried without duplicate evidence.
  Future<void> _discardUnacceptedCopy(String path, String photoId) async {
    try {
      if (DBHelper.currentInspectorId != _inspectorId) return;
      final rows = await DBHelper.getLocalPhotos(widget.task.id);
      if (rows.any((row) => row['id'] == photoId)) return;
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (e) {
      debugPrint('Unaccepted copy retained: $e');
    }
  }

  Future<Directory> _evidenceDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    if (!_sameInspection) throw StateError('The active inspection changed');
    return Directory(
      '${documents.path}/inspection_evidence/'
      '${Uri.encodeComponent(_inspectorId!)}/${Uri.encodeComponent(widget.task.id)}',
    ).create(recursive: true);
  }

  Future<void> _ensureLocationReference() async {
    if (_referenceEnsuring || !_sameInspection) return;
    Map<String, dynamic>? existing;
    for (final photo in _capturedPhotos) {
      if (isLocationReferencePhoto(photo)) {
        existing = photo;
        break;
      }
    }
    if (existing != null) {
      final existingPath = existing['photoPath'] as String?;
      if (existingPath == null ||
          PhotoSourceResolver.classify(existingPath) !=
              PhotoSourceKind.localFile ||
          _provider.isReworkMode ||
          File(existingPath).existsSync()) {
        return;
      }
      // The row survived but the image did not: regenerate the same stable
      // file and re-save the same deterministic identity below.
    }

    setState(() {
      _referenceEnsuring = true;
      _referenceError = null;
    });
    try {
      if (_pendingReference == null) {
        final snapshot = _provider.gpsVerification;
        if (snapshot == null) {
          throw StateError(
            'Step 2 GPS verification is unavailable on this device.',
          );
        }
        final cached = await DBHelper.getCachedJob(widget.task.id);
        if (!_sameInspection) return;
        final parcelLat = (cached?['parcel_lat'] as num?)?.toDouble();
        final parcelLng = (cached?['parcel_lng'] as num?)?.toDouble();
        if (parcelLat == null || parcelLng == null) {
          throw StateError(
            'The recorded parcel reference point is unavailable on this device.',
          );
        }
        final generatedAt =
            DateTime.tryParse(existing?['capturedAt'] as String? ?? '') ??
            DateTime.now();
        final bytes = await SiteLocationReferenceService.render(
          jobId: widget.task.id,
          round: widget.task.inspectionRoundNumber,
          applicant: widget.task.name,
          address: widget.task.locationAddress,
          verifiedLatitude: snapshot.latitude,
          verifiedLongitude: snapshot.longitude,
          verifiedAt: snapshot.verifiedAt,
          verifiedAccuracyMeters: snapshot.accuracyMeters,
          parcelLatitude: parcelLat,
          parcelLongitude: parcelLng,
          generatedAt: generatedAt,
        );
        if (!_sameInspection) return;
        final directory = await _evidenceDirectory();
        if (!_sameInspection) return;
        final file = File(
          existing?['photoPath'] as String? ??
              '${directory.path}/${SiteLocationReferenceService.fileName(widget.task.id, widget.task.inspectionRoundNumber)}',
        );
        await file.writeAsBytes(bytes, flush: true);
        if (!_sameInspection) return;
        _pendingReference =
            existing ??
            {
              'id': SiteLocationReferenceService.photoId(
                widget.task.id,
                widget.task.inspectionRoundNumber,
              ),
              'photoPath': file.path,
              'notes': kSiteLocationReferenceNotes,
              'latitude': snapshot.latitude,
              'longitude': snapshot.longitude,
              'capturedAt': GeotagService.storageTimestamp(generatedAt),
              'isLocationReference': true,
            };
      }
      if (!_sameInspection) return;
      if (!await _provider.persistPhoto(
        _pendingReference!,
        task: widget.task,
        inspectorId: _inspectorId!,
      )) {
        throw StateError(
          'The location reference could not be saved on this device.',
        );
      }
      _pendingReference = null;
    } catch (e) {
      if (!_sameInspection) return;
      setState(() {
        _referenceError =
            '${e is StateError ? e.message : 'The location reference could not be prepared on this device.'} '
            'Real site photos are still accepted.';
      });
    } finally {
      if (mounted) setState(() => _referenceEnsuring = false);
    }
  }

  Future<void> _finishAndContinue() async {
    if (_isSaving || _isSavingPhoto || !_sameInspection) return;
    final realCount = _capturedPhotos
        .where((photo) => !isLocationReferencePhoto(photo))
        .length;
    if (realCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Capture at least one camera photo.',
            style: InsightTheme.inter(13, c: Colors.white),
          ),
          backgroundColor: InsightTheme.ink,
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _referenceFuture;
      if (!_sameInspection) return;
      await _provider.persistCapturedPhotos();
      if (!mounted || !_sameInspection) return;
      InspectionProgress.instance.markStepComplete(3);
      unawaited(_provider.saveStepPhotos());
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InspectionChecklistScreen(
            task: widget.task,
            capturedPhotos: _capturedPhotos,
          ),
        ),
      );
    } catch (_) {
      if (!mounted || !_sameInspection) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Photos could not be saved on this device. Stay on Step 3 and retry.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    if (!_isSavingPhoto) _discardPendingCapture();
    _notesController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<InspectionProvider>();
    return SensitiveScreen(
      child: PopScope(
        canPop: !_isSavingPhoto && !_isCapturing && !_isSaving,
        child: _isCameraMode ? _buildCameraMode() : _buildGridMode(),
      ),
    );
  }

  Widget _buildGridMode() {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    return PopScope(
      canPop:
          !context.read<InspectionProvider>().isReworkMode &&
          InspectionProgress.instance.currentStep > 1,
      onPopInvokedWithResult: (didPop, _) {
        if (_isSaving) return;
        if (didPop) {
          context.read<InspectionProvider>().saveStepPhotos();
          return;
        }
        handleInspectionExit(
          context,
          onSaveProgress: () =>
              context.read<InspectionProvider>().saveStepPhotos(),
          isReworkMode: context.read<InspectionProvider>().isReworkMode,
        );
      },
      child: Scaffold(
        backgroundColor: InsightTheme.bg,
        body: FieldFormBody(
          header: InspectionStepHeader(
            formStyle: true,
            title: 'Photographic Evidence',
            subtitle: widget.task.location,
            stepNumber: 3,
            stepSubtitle: 'CAPTURE EVIDENCE',
            onBack: () => handleInspectionExit(
              context,
              onSaveProgress: () =>
                  context.read<InspectionProvider>().saveStepPhotos(),
              isReworkMode: context.read<InspectionProvider>().isReworkMode,
            ),
          ),
          action: Row(
            children: [
              if (context.watch<InspectionProvider>().isReworkMode) ...[
                Expanded(
                  child: FieldPrimaryButton(
                    label: 'Save',
                    busy: _isSaving,
                    onPressed: _isSaving
                        ? null
                        : () async {
                            setState(() => _isSaving = true);
                            final ok = await context
                                .read<InspectionProvider>()
                                .saveStepPhotos();
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Save failed.')),
                              );
                            }
                          },
                  ),
                ),
              ] else ...[
                Expanded(
                  child: FieldPrimaryButton(
                    label: 'Continue to Checklist',
                    busy: _isSaving,
                    onPressed: _isSaving ? null : _finishAndContinue,
                  ),
                ),
              ],
            ],
          ),
          children: [
            FieldSectionHeading(
              title: 'Site photos',
              hint:
                  'Attach at least one photo to continue. Up to '
                  '$maxPhotos site photos; the generated location reference is '
                  'not counted against that limit.',
              trailing: Text(
                '${_capturedPhotos.where((p) => !isLocationReferencePhoto(p)).length} / $maxPhotos photos',
                style: InsightTheme.inter(
                  13,
                  w: FontWeight.w600,
                  c: InsightTheme.blueInk,
                ),
              ),
            ),
            if (_referenceEnsuring)
              const _ReferenceNotice(
                text: 'Preparing the Site Location Reference…',
                busy: true,
              )
            else if (_referenceError != null)
              _ReferenceNotice(
                text: _referenceError!,
                onRetry: () => _referenceFuture = _ensureLocationReference(),
              ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent:
                    220 * MediaQuery.textScalerOf(context).scale(14) / 14,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1,
              ),
              itemCount:
                  _capturedPhotos.length +
                  (_capturedPhotos
                              .where((p) => !isLocationReferencePhoto(p))
                              .length <
                          maxPhotos
                      ? 1
                      : 0),
              itemBuilder: (context, index) {
                if (index < _capturedPhotos.length) {
                  final paths = inspectionDisplayPaths(
                    _capturedPhotos
                        .map((p) => p['photoPath'] as String)
                        .toList(),
                    widget.task.id,
                    widget.task.photoDetails,
                    widget.task.photoPaths,
                  );
                  final photo = _capturedPhotos[index];
                  final isReference = isLocationReferencePhoto(photo);
                  final realIndex =
                      _capturedPhotos
                          .take(index)
                          .where((p) => !isLocationReferencePhoto(p))
                          .length +
                      1;
                  return _PhotoCell(
                    photoPath: paths[index],
                    allPhotoPaths: paths,
                    photoDetails: _capturedPhotos,
                    index: index,
                    isLocationReference: isReference,
                    label: isReference
                        ? 'Location reference'
                        : 'Photo $realIndex',
                    onRemove: isReference
                        ? null
                        : () => _confirmRemovePhoto(index),
                  );
                }
                return _AddPhotoCell(
                  onTap: () => setState(() => _isCameraMode = true),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraMode() {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
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
                colors: [
                  Color(0xFF0B1623),
                  Color(0xFF111D2D),
                  Color(0xFF0D1B2A),
                ],
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final previewHeight =
                    (constraints.maxHeight * (hasCapturedPhoto ? 0.50 : 0.72))
                        .clamp(280.0, 540.0);

                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.14),
                                ),
                              ),
                              child: IconButton(
                                tooltip: 'Close camera',
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                onPressed: _isSavingPhoto || _isCapturing
                                    ? null
                                    : () => setState(() {
                                        _isCameraMode = false;
                                        _discardPendingCapture();
                                      }),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Capture Site Photo',
                                style: InsightTheme.poppins(
                                  18,
                                  w: FontWeight.w700,
                                  c: Colors.white,
                                ),
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
                            borderRadius: InsightTheme.roundedLg,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.14),
                              width: 1.2,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            children: [
                              Positioned.fill(child: _buildCameraPreviewArea()),
                              if (!hasCapturedPhoto)
                                Positioned(
                                  left: 16,
                                  right: 16,
                                  bottom: 18,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.52,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.12,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      _previewFooterLines.join('\n'),
                                      maxLines: 5,
                                      overflow: TextOverflow.ellipsis,
                                      style: InsightTheme.mono(
                                        11,
                                        c: Colors.white,
                                        ls: 0.08,
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
                                        colors: [
                                          Colors.black,
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (!hasCapturedPhoto &&
                          _initializeControllerFuture != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: FutureBuilder<void>(
                            future: _initializeControllerFuture,
                            builder: (context, snapshot) =>
                                snapshot.connectionState != ConnectionState.done
                                ? const SizedBox.shrink()
                                : Semantics(
                                    button: true,
                                    label: 'Capture site photo',
                                    child: GestureDetector(
                                      onTap: _isCapturing
                                          ? null
                                          : _capturePhoto,
                                      child: Container(
                                        width: 78,
                                        height: 78,
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 4,
                                          ),
                                        ),
                                        child: _isCapturing
                                            ? const CircularProgressIndicator(
                                                color: Colors.white,
                                              )
                                            : const DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      if (hasCapturedPhoto) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE7F3FF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFB9D8FF),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.info_outline_rounded,
                                  color: Color(0xFF1F6FEB),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Save the photo evidence before leaving this screen or it will disappear.',
                                    style: InsightTheme.inter(
                                      12,
                                      c: const Color(0xFF1D4ED8),
                                      w: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: InsightTheme.surface,
                            borderRadius: InsightTheme.roundedMd,
                            border: Border.all(color: InsightTheme.line),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const FieldSectionHeading(
                                title: 'Photo notes',
                                bottomSpacing: 8,
                                hint: 'Optional context for this photo.',
                              ),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: InsightTheme.bg,
                                  borderRadius: InsightTheme.roundedSm,
                                  border: Border.all(color: InsightTheme.line),
                                ),
                                child: TextField(
                                  controller: _notesController,
                                  enabled: !_isSavingPhoto,
                                  keyboardType: TextInputType.multiline,
                                  textInputAction: TextInputAction.newline,
                                  minLines: 3,
                                  maxLines: 8,
                                  style: InsightTheme.inter(
                                    16,
                                    c: InsightTheme.ink,
                                  ),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'Add field observations here...',
                                    hintStyle: InsightTheme.inter(
                                      14,
                                      c: InsightTheme.ink3,
                                    ),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: FieldPrimaryButton(
                                  label: 'Save Photo',
                                  busy: _isSavingPhoto,
                                  onPressed: _isSavingPhoto
                                      ? null
                                      : _savePhotoAndReturnToGrid,
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
          Image.file(File(_capturedPhotoPath!), fit: BoxFit.contain),
          Positioned(
            top: 16,
            right: 16,
            child: TextButton.icon(
              onPressed: _isSavingPhoto ? null : _retakePhoto,
              style: TextButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.65),
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: Text(
                'Retake',
                style: InsightTheme.inter(
                  14,
                  w: FontWeight.w600,
                  c: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (_cameraController == null || _initializeControllerFuture == null) {
      return _cameraUnavailable();
    }
    return FutureBuilder<void>(
      future: _initializeControllerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: ImapsLoadingIndicator(size: 60));
        }
        if (snapshot.hasError) return _cameraUnavailable();
        return CameraPreview(_cameraController!);
      },
    );
  }
}

class _PhotoCell extends StatelessWidget {
  final String photoPath;
  final List<String> allPhotoPaths;
  final List<Map<String, dynamic>> photoDetails;
  final int index;
  final bool isLocationReference;
  final String label;
  final VoidCallback? onRemove;
  const _PhotoCell({
    required this.photoPath,
    required this.allPhotoPaths,
    required this.photoDetails,
    required this.index,
    required this.isLocationReference,
    required this.label,
    required this.onRemove,
  });
  @override
  Widget build(BuildContext context) {
    // Use the same private-storage read contract as the fullscreen viewer.
    return Semantics(
      button: true,
      label: isLocationReference
          ? 'View generated site location reference'
          : 'View ${label.toLowerCase()}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: InsightTheme.roundedMd,
          onTap: () => openFullscreenPhotoViewer(
            context,
            allPhotoPaths,
            index,
            photoDetails: photoDetails,
            jobId: context.read<InspectionProvider>().activeTask?.id,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isLocationReference
                    ? InsightTheme.blueInk
                    : InsightTheme.line,
                width: isLocationReference ? 2 : 1,
              ),

              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A141628),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AdaptivePhotoImage(path: photoPath),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          label,
                          style: InsightTheme.inter(12, c: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
                if (isLocationReference)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: InsightTheme.blueInk,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'SYSTEM',
                        style: InsightTheme.inter(
                          10,
                          w: FontWeight.w700,
                          c: Colors.white,
                          ls: 0.6,
                        ),
                      ),
                    ),
                  ),
                if (onRemove != null)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: IconButton(
                      tooltip: 'Remove $label',
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        onRemove!();
                      },
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.65),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.close_rounded, size: 20),
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

class _ReferenceNotice extends StatelessWidget {
  final String text;
  final bool busy;
  final VoidCallback? onRetry;
  const _ReferenceNotice({required this.text, this.busy = false, this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: InsightTheme.roundedMd,
        border: Border.all(color: InsightTheme.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: InsightTheme.blueInk,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: InsightTheme.inter(13, c: InsightTheme.ink2, h: 1.35),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _AddPhotoCell extends StatelessWidget {
  final VoidCallback onTap;
  const _AddPhotoCell({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        color: InsightTheme.surface,
        borderRadius: InsightTheme.roundedMd,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Container(
            decoration: BoxDecoration(
              color: InsightTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: InsightTheme.lineStrong, width: 1.5),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add_a_photo_outlined,
                      color: InsightTheme.blueInk,
                      size: 28,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Add site photo',
                      textAlign: TextAlign.center,
                      style: InsightTheme.inter(
                        14,
                        w: FontWeight.w600,
                        c: InsightTheme.blueInk,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
