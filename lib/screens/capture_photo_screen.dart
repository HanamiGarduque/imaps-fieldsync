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

/// ==================================================================
/// THEME COLORS & TOKENS (InSight Blue Glass & Gradient Theme)
/// ==================================================================
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
  
  static const Color line = Color(0x12141628); // ~rgba(20,22,40,0.07)
  static const Color lineStrong = Color(0x21141628); // ~rgba(20,22,40,0.13)
  
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w600, Color? c, double? h, double? ls}) => 
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? ink, height: h ?? 1.2, letterSpacing: ls);
      
  static TextStyle inter(double size, {FontWeight w = FontWeight.w400, Color? c, double? h}) => 
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? ink2, height: h ?? 1.5);
      
  static TextStyle jetBrains(double size, {FontWeight w = FontWeight.w500, Color? c, double? ls}) => 
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: c ?? ink3, letterSpacing: ls);
}

/// ==================================================================
/// SCREEN 10 — PHOTO EVIDENCE (Includes Camera UI)
/// ==================================================================
class CapturePhotoScreen extends StatefulWidget {
  const CapturePhotoScreen({super.key});

  @override
  State<CapturePhotoScreen> createState() => _CapturePhotoScreenState();
}

class _CapturePhotoScreenState extends State<CapturePhotoScreen> {
  // --- New State for Grid ---
  final List<Map<String, dynamic>> _capturedPhotos = [];
  bool _isCameraMode = false; // Toggles between Grid View and Camera View

  // --- Original Preserved Camera State ---
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
  }

  // Original Camera Init Logic
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
    }
  }

  // Original Location Logic
  Future<void> _fetchLocation() async {
    try {
      final position = await LocationService.getCurrentLocation();
      if (mounted) setState(() => _currentPosition = position);
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  String _monthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  String get _geotagText {
    final now = DateTime.now();
    final dateStr =
        '${_monthName(now.month)} ${now.day.toString().padLeft(2, '0')}, ${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final coords = _currentPosition != null
        ? '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}'
        : 'Locating...';
    return '$dateStr\n$coords';
  }

  // Original Capture Logic
  Future<void> _capturePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      final xFile = await _cameraController!.takePicture();
      final rawBytes = await xFile.readAsBytes();

      final geotaggedBytes = GeotagService.embedGeotag(
        photoBytes: rawBytes,
        lines: _geotagText.split('\n'),
      );

      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'inspection_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedFile = File('${directory.path}/$fileName');
      await savedFile.writeAsBytes(geotaggedBytes);

      if (mounted) setState(() => _capturedPhotoPath = savedFile.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to capture photo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _retakePhoto() => setState(() => _capturedPhotoPath = null);

  // Modified Save Logic to append to list instead of popping immediately
  void _savePhotoAndReturnToGrid() {
    if (_capturedPhotoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture a photo first.')),
      );
      return;
    }

    setState(() {
      _capturedPhotos.add({
        'photoPath': _capturedPhotoPath,
        'notes': _notesController.text,
        'latitude': _currentPosition?.latitude,
        'longitude': _currentPosition?.longitude,
        'capturedAt': DateTime.now().toIso8601String(),
      });
      _isCameraMode = false;
      _capturedPhotoPath = null;
      _notesController.clear();
    });
  }

  void _finishAndContinue() {
    // Return the last captured photo to maintain contract with FieldFindingsScreen
    Navigator.pop(context, _capturedPhotos.isNotEmpty ? _capturedPhotos.last : null);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _isCameraMode ? _buildCameraMode() : _buildGridMode();
  }

  // ==================================================================
  // 1. GRID MODE (Matches HTML Photo Evidence Screen)
  // ==================================================================
  Widget _buildGridMode() {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      body: Stack(
        children: [
          // Background Gradient Blobs
          Positioned(
            top: -60, right: -60,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 260, height: 260,
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withOpacity(0.20)),
              ),
            ),
          ),
          Positioned(
            bottom: -80, left: -80,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 220, height: 220,
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withOpacity(0.10)),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      _GlassBackButton(onTap: () => Navigator.pop(context)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Photo evidence', style: InsightTheme.poppins(17, w: FontWeight.w700, c: InsightTheme.ink)),
                      ),
                    ],
                  ),
                ),

                // Progress Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 6,
                        width: double.infinity,
                        decoration: BoxDecoration(color: InsightTheme.surface2, borderRadius: BorderRadius.circular(4)),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 0.5, // 50% Step 3 of 6
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [InsightTheme.blue1, InsightTheme.blue2]),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('STEP 3 OF 6', style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.5)),
                          Text(' — EVIDENCE · ${_capturedPhotos.length} PHOTOS CAPTURED', style: InsightTheme.jetBrains(10, c: InsightTheme.ink3, ls: 0.5)),
                        ],
                      ),
                    ],
                  ),
                ),

                // Grid View
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                    physics: const BouncingScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1,
                    ),
                    itemCount: _capturedPhotos.length + 1, // Photos + Add Button
                    itemBuilder: (context, index) {
                      if (index < _capturedPhotos.length) {
                        final photo = _capturedPhotos[index];
                        return _PhotoCell(photoPath: photo['photoPath'] as String);
                      } else {
                        return _AddPhotoCell(onTap: () => setState(() => _isCameraMode = true));
                      }
                    },
                  ),
                ),

                // Bottom Action Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: ElevatedButton(
                    onPressed: _finishAndContinue,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: Colors.transparent, 
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ).copyWith(elevation: WidgetStateProperty.all(0)),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [InsightTheme.blue1, InsightTheme.blue2],
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: InsightTheme.blue1.withOpacity(0.32), blurRadius: 22, offset: const Offset(0, 10))],
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        constraints: const BoxConstraints(minHeight: 50),
                        child: Text('Continue to findings', style: InsightTheme.poppins(14.5, w: FontWeight.w600, c: Colors.white)),
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

  // ==================================================================
  // 2. CAMERA MODE (Matches the screenshot with the bottom sheet)
  // ==================================================================
  Widget _buildCameraMode() {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark camera background
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top App Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                    onPressed: () {
                      setState(() {
                        _isCameraMode = false;
                        _capturedPhotoPath = null;
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  Text('Capture Site Photo', style: InsightTheme.poppins(18, w: FontWeight.w600, c: Colors.white)),
                ],
              ),
            ),
            
            // Camera Preview Area
            Expanded(
              flex: 5,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(32),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildCameraPreviewArea(),
              ),
            ),
            
            const SizedBox(height: 16),

            // Bottom Sheet (Notes & Save)
            Expanded(
              flex: 4,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                decoration: const BoxDecoration(
                  color: InsightTheme.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Inspection Notes', style: InsightTheme.poppins(16, w: FontWeight.w700, c: InsightTheme.ink)),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: InsightTheme.surface2,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: InsightTheme.line),
                        ),
                        child: TextField(
                          controller: _notesController,
                          maxLines: null,
                          expands: true,
                          style: InsightTheme.inter(14, c: InsightTheme.ink),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Add field observations here...',
                            hintStyle: InsightTheme.inter(14, c: InsightTheme.ink3),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _savePhotoAndReturnToGrid,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: InsightTheme.blue1,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text('Save & Continue', style: InsightTheme.poppins(15, w: FontWeight.w600, c: Colors.white)),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
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
        ],
      );
    }

    if (_cameraController == null || _initializeControllerFuture == null) {
      return const Center(child: CircularProgressIndicator(color: InsightTheme.blue1));
    }

    return FutureBuilder<void>(
      future: _initializeControllerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: InsightTheme.blue1));
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(_cameraController!),
            // Geotag Overlay
            Positioned(
              left: 16, bottom: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Text(
                  _geotagText,
                  style: GoogleFonts.firaCode(color: Colors.white, fontSize: 11, height: 1.5),
                ),
              ),
            ),
            // Capture Button
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: GestureDetector(
                  onTap: _capturePhoto,
                  child: Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: Colors.white.withOpacity(0.2),
                    ),
                    child: Center(
                      child: _isCapturing
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Container(
                              width: 56, height: 56,
                              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            ),
                    ),
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

/// ==================================================================
/// COMPONENT WIDGETS
/// ==================================================================

class _PhotoCell extends StatelessWidget {
  final String photoPath;
  const _PhotoCell({required this.photoPath});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: InsightTheme.line),
        image: DecorationImage(
          image: FileImage(File(photoPath)),
          fit: BoxFit.cover,
        ),
        boxShadow: const [BoxShadow(color: Color(0x0A141628), blurRadius: 2, offset: Offset(0, 1))],
      ),
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            'Captured', 
            style: InsightTheme.jetBrains(8, c: Colors.white),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
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
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          color: InsightTheme.blueTint,
          borderRadius: BorderRadius.circular(16),
          // Using a solid border here to simulate the dashed look without external packages
          border: Border.all(color: InsightTheme.blue1.withOpacity(0.5), width: 1.5),
        ),
        child: const Center(
          child: Icon(Icons.add_rounded, color: InsightTheme.blueInk, size: 28),
        ),
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
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withOpacity(0.65)),
          boxShadow: const [BoxShadow(color: Color(0x0F141628), blurRadius: 14, offset: Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: const Center(
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: InsightTheme.ink),
            ),
          ),
        ),
      ),
    );
  }
}