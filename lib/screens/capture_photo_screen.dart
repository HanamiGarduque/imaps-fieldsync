import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import '../services/location_service.dart';
import '../services/geotag_service.dart';

class CapturePhotoScreen extends StatefulWidget {
  const CapturePhotoScreen({super.key});

  @override
  State<CapturePhotoScreen> createState() => _CapturePhotoScreenState();
}

class _CapturePhotoScreenState extends State<CapturePhotoScreen> {
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
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B1140),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text(
                    'Capture Photo',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 6,
              child: Container(
                width: double.infinity,
                color: const Color(0xFF6E6E78),
                child: _buildPreviewArea(),
              ),
            ),
            Expanded(
              flex: 4,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                decoration: const BoxDecoration(
                  color: Color(0xFF241A55),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Notes',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF352A70),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: _notesController,
                          maxLines: null,
                          expands: true,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Add a note...',
                            hintStyle: TextStyle(color: Colors.white54),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _savePhoto,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF241A55),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Save Photo'),
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
    if (_capturedPhotoPath != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(_capturedPhotoPath!), fit: BoxFit.cover),
          Positioned(
            top: 14,
            right: 14,
            child: GestureDetector(
              onTap: _retakePhoto,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Retake', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ),
        ],
      );
    }

    if (_cameraController == null || _initializeControllerFuture == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return FutureBuilder<void>(
      future: _initializeControllerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(_cameraController!),
            Positioned(
              left: 14,
              bottom: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _geotagText,
                  style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.4),
                ),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.only(top: 40),
                child: GestureDetector(
                  onTap: _capturePhoto,
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Center(
                      child: _isCapturing
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Icon(Icons.camera_alt, color: Colors.white70),
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