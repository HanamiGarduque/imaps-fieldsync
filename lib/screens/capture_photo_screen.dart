import 'dart:io';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/location_service.dart';
import '../services/geotag_service.dart';

import 'tasks_screen.dart';
import 'inspection_progress.dart';
import 'inspection_checklist_screen.dart';
import 'package:provider/provider.dart';
import '../providers/inspection_provider.dart';

class InsightTheme {
  static const Color bg = Color(0xFFF2F4FB);
  static const Color surface = Colors.white;
  static const Color surface2 = Color(0xFFEEF1FC);
  static const Color ink = Color(0xFF12141F);
  static const Color ink2 = Color(0xFF666C82);
  static const Color ink3 = Color(0xFFA2A7BC);
  static const Color blue1 = Color(0xFF3D6BFF);
  static const Color blue2 = Color(0xFF0B2FBF);
  static const Color blueTint = Color(0xFFE7EDFF);
  static const Color blueInk = Color(0xFF1A3FC4);
  static const Color line = Color(0x1A141628); 
  static const Color lineStrong = Color(0x2A141628); 
  
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w600, Color? c, double? h, double? ls}) => GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? ink, height: h ?? 1.2, letterSpacing: ls);
  static TextStyle inter(double size, {FontWeight w = FontWeight.w400, Color? c, double? h, double? ls}) => GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? ink2, height: h ?? 1.5, letterSpacing: ls);
  static TextStyle jetBrains(double size, {FontWeight w = FontWeight.w500, Color? c, double? ls}) => GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: c ?? ink3, letterSpacing: ls);
}

class CapturePhotoScreen extends StatefulWidget {
  final TaskItem task;
  const CapturePhotoScreen({super.key, required this.task});

  @override
  State<CapturePhotoScreen> createState() => _CapturePhotoScreenState();
}

class _CapturePhotoScreenState extends State<CapturePhotoScreen> {
  final List<Map<String, dynamic>> _capturedPhotos = [];
  bool _isCameraMode = false; 

  final TextEditingController _notesController = TextEditingController();
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;
  Position? _currentPosition;
  String? _capturedPhotoPath;
  bool _isCapturing = false;

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

  void _savePhotoAndReturnToGrid() {
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
    Navigator.push(context, MaterialPageRoute(builder: (_) => InspectionChecklistScreen(task: widget.task, capturedPhotos: _capturedPhotos)));
  }

  @override
  void dispose() { _notesController.dispose(); _cameraController?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => _isCameraMode ? _buildCameraMode() : _buildGridMode();

  Widget _buildGridMode() {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    return Scaffold(
      backgroundColor: InsightTheme.bg,
      body: Stack(
        children: [
          Positioned(top: -60, right: -60, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40), child: Container(width: 260, height: 260, decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withValues(alpha: 0.20))))),
          Positioned(bottom: -80, left: -80, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40), child: Container(width: 220, height: 220, decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withValues(alpha: 0.10))))),

          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      _GlassBackButton(onTap: () => Navigator.pop(context)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Photographic Evidence', style: InsightTheme.poppins(17, w: FontWeight.w700)),
                            Text(widget.task.location, style: InsightTheme.inter(12, c: InsightTheme.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 6, decoration: BoxDecoration(color: InsightTheme.surface2, borderRadius: BorderRadius.circular(4)),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft, widthFactor: 3/6,
                          child: Container(decoration: BoxDecoration(gradient: const LinearGradient(colors: [InsightTheme.blue1, InsightTheme.blue2]), borderRadius: BorderRadius.circular(4))),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('STEP 3 OF 6', style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.5)),
                          Text(' — CAPTURE SITE PHOTOS', style: InsightTheme.jetBrains(10, c: InsightTheme.ink3, ls: 0.5)),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    physics: const BouncingScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1),
                    itemCount: _capturedPhotos.length + 1,
                    itemBuilder: (context, index) {
                      if (index < _capturedPhotos.length) return _PhotoCell(photoPath: _capturedPhotos[index]['photoPath'] as String);
                      return _AddPhotoCell(onTap: () => setState(() => _isCameraMode = true));
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraMode() {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28), onPressed: () => setState(() { _isCameraMode = false; _capturedPhotoPath = null; })),
                  const SizedBox(width: 8),
                  Text('Capture Site Photo', style: InsightTheme.poppins(18, w: FontWeight.w600, c: Colors.white)),
                ],
              ),
            ),
            Expanded(
              flex: 5,
              child: Container(
                width: double.infinity, margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(24)),
                clipBehavior: Clip.antiAlias,
                child: _buildCameraPreviewArea(),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              flex: 4,
              child: Container(
                width: double.infinity, padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                decoration: const BoxDecoration(color: InsightTheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Inspection Notes', style: InsightTheme.poppins(15, w: FontWeight.w700, c: InsightTheme.ink)),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: InsightTheme.bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: InsightTheme.line)),
                        child: TextField(
                          controller: _notesController, maxLines: null, expands: true,
                          style: InsightTheme.inter(14, c: InsightTheme.ink),
                          decoration: InputDecoration(border: InputBorder.none, hintText: 'Add field observations here...', hintStyle: InsightTheme.inter(14, c: InsightTheme.ink3)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _savePhotoAndReturnToGrid,
                        style: ElevatedButton.styleFrom(backgroundColor: InsightTheme.blue1, padding: const EdgeInsets.symmetric(vertical: 18), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        child: Text('Save Photo', style: InsightTheme.poppins(15, w: FontWeight.w600, c: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
    if (_cameraController == null || _initializeControllerFuture == null) return const Center(child: CircularProgressIndicator(color: InsightTheme.blue1));
    return FutureBuilder<void>(
      future: _initializeControllerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator(color: InsightTheme.blue1));
        return Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(_cameraController!),
            Positioned(
              left: 16, bottom: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
                child: Text(_geotagText, style: GoogleFonts.firaCode(color: Colors.white, fontSize: 11, height: 1.4)),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: GestureDetector(
                  onTap: _capturePhoto,
                  child: Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), color: Colors.white.withValues(alpha: 0.2)),
                    child: Center(child: _isCapturing ? const CircularProgressIndicator(color: Colors.white) : Container(width: 56, height: 56, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))),
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
  const _PhotoCell({required this.photoPath});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16), border: Border.all(color: InsightTheme.line),
        image: DecorationImage(image: FileImage(File(photoPath)), fit: BoxFit.cover),
        boxShadow: const [BoxShadow(color: Color(0x0A141628), blurRadius: 4, offset: Offset(0, 2))],
      ),
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
          child: Text('Captured', style: InsightTheme.jetBrains(9, c: Colors.white)),
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

class _GlassBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBackButton({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: 0.65)), boxShadow: const [BoxShadow(color: Color(0x0F141628), blurRadius: 10, offset: Offset(0, 4))]),
        child: ClipRRect(borderRadius: BorderRadius.circular(14), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: const Center(child: Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: InsightTheme.ink))))),
      ),
    );
  }
}