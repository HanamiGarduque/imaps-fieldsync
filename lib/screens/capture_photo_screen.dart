import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/location_service.dart';
import '../services/geotag_service.dart';

/// Design Tokens 
class AppColors {
  static const headerDark = Color(0xFF0F172A);
  static const headerAccent = Color(0xFF4F46E5);
  static const bgLight = Color(0xFFF8FAFC);
  static const surface = Colors.white;
}

class AppText {
  static TextStyle display(double size, {FontWeight w = FontWeight.w700, Color? c}) => 
      GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: w, color: c ?? Colors.white, letterSpacing: -0.5);
  static TextStyle body(double size, {FontWeight w = FontWeight.w500, Color? c}) => 
      GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: w, color: c ?? const Color(0xFF475569));
}

class CapturePhotoScreen extends StatefulWidget {
  const CapturePhotoScreen({super.key});

  @override
  State<CapturePhotoScreen> createState() => _CapturePhotoScreenState();
}

class _CapturePhotoScreenState extends State<CapturePhotoScreen> {
  // ALL Original State Variables Preserved[cite: 3]
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

  // Original Camera Init Logic[cite: 3]
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

  // Original Location Logic[cite: 3]
  Future<void> _fetchLocation() async {
    try {
      final position = await LocationService.getCurrentLocation();
      if (mounted) setState(() => _currentPosition = position);
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  // Original Date formatting[cite: 3]
  String _monthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  // Original Geotag Logic[cite: 3]
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

  // Original Capture Logic[cite: 3]
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

  // Original Retake Logic[cite: 3]
  void _retakePhoto() => setState(() => _capturedPhotoPath = null);

  // Original Save Logic[cite: 3]
  void _savePhoto() {
    if (_capturedPhotoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture a photo first.')),
      );
      return;
    }

    Navigator.pop(context, {
      'photoPath': _capturedPhotoPath,
      'notes': _notesController.text,
      'latitude': _currentPosition?.latitude,
      'longitude': _currentPosition?.longitude,
      'capturedAt': DateTime.now().toIso8601String(),
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    _cameraController?.dispose(); // Original dispose[cite: 3]
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    return Scaffold(
      backgroundColor: AppColors.headerDark, // Sleek dark background for camera UI
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top App Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Text('Capture Site Photo', style: AppText.display(18)),
                ],
              ),
            ),
            
            // Camera / Image Preview Area
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
                child: _buildPreviewArea(),
              ),
            ),
            
            const SizedBox(height: 16),

            // Modern Bottom Sheet (Notes & Save)
            Expanded(
              flex: 4,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                decoration: const BoxDecoration(
                  color: AppColors.surface, // Clean white UI
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(40),
                    topRight: Radius.circular(40),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Inspection Notes', style: AppText.display(16, c: AppColors.headerDark)),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.bgLight,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: TextField(
                          controller: _notesController, // Original controller[cite: 3]
                          maxLines: null,
                          expands: true,
                          style: AppText.body(15, c: AppColors.headerDark),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Add field observations here...',
                            hintStyle: AppText.body(15, c: const Color(0xFF94A3B8)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _savePhoto, // Original save trigger[cite: 3]
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.headerAccent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text('Save & Continue', style: AppText.display(15)),
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

  Widget _buildPreviewArea() {
    // Original photo preview logic[cite: 3]
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
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text('Retake', style: AppText.body(13, c: Colors.white, w: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Original loading logic[cite: 3]
    if (_cameraController == null || _initializeControllerFuture == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.headerAccent));
    }

    return FutureBuilder<void>(
      future: _initializeControllerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: AppColors.headerAccent));
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
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Text(
                  _geotagText, // Original geotag getter[cite: 3]
                  style: GoogleFonts.firaCode(color: Colors.white, fontSize: 11, height: 1.5),
                ),
              ),
            ),

            // Premium Modern Capture Button
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: GestureDetector(
                  onTap: _capturePhoto, // Original trigger[cite: 3]
                  child: Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: Colors.white.withValues(alpha: 0.2),
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