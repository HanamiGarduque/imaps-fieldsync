import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tasks_screen.dart'; // Ensure TaskItem is accessible here
import 'capture_photo_screen.dart';

/// Design Tokens
class AppColors {
  static const headerDark = Color(0xFF0F172A);
  static const headerAccent = Color(0xFF4F46E5);
  static const bgLight = Color(0xFFF8FAFC);
  static const surface = Colors.white;
  static const textDark = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF475569);
  static const divider = Color(0xFFE2E8F0);
  static const statusProgress = Color(0xFF10B981);
}

class AppText {
  static TextStyle display(double size, {FontWeight w = FontWeight.w700, Color? c}) => 
      GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: w, color: c ?? Colors.white, letterSpacing: -0.5);
  static TextStyle body(double size, {FontWeight w = FontWeight.w500, Color? c}) => 
      GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: w, color: c ?? AppColors.textSecondary);
}

class ParcelDetailScreen extends StatefulWidget {
  final TaskItem task;
  const ParcelDetailScreen({super.key, required this.task});

  @override
  State<ParcelDetailScreen> createState() => _ParcelDetailScreenState();
}

class _ParcelDetailScreenState extends State<ParcelDetailScreen> {
  // Original state preserved[cite: 4]
  String _boundaryStatus = 'Matches recorded area';
  String _landUseStatus = 'Consistent with zoning';
  final List<String> _photos = [];

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: Column(
        children: [
          // 1. Premium Gradient Header
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.headerDark, AppColors.headerAccent],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Bar
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 8, height: 8,
                              decoration: BoxDecoration(
                                color: Colors.greenAccent, 
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.5), blurRadius: 8)],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('iMAPS-FieldSync', style: AppText.body(13, c: Colors.white, w: FontWeight.w600)),
                          ],
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Text('Offline Mode', style: AppText.body(11, c: Colors.white, w: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Titles
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.task.name, style: AppText.display(28)),
                          const SizedBox(height: 4),
                          Text(
                            'Inspection No: ${widget.task.inspectionNo}',
                            style: AppText.body(14, c: Colors.white.withValues(alpha: 0.7)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2. Main Content Body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              physics: const BouncingScrollPhysics(),
              children: [
                // Modern Map Placeholder
                Container(
                  height: 160,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.headerAccent.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.headerAccent.withValues(alpha: 0.1)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map_rounded, color: AppColors.headerAccent.withValues(alpha: 0.5), size: 40),
                      const SizedBox(height: 12),
                      Text(
                        'Map pinpointing parcel location',
                        style: AppText.body(14, c: AppColors.headerAccent.withValues(alpha: 0.8), w: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Forms
                Text('Actual lot boundaries vs 300 sqm', style: AppText.body(14, c: AppColors.textDark, w: FontWeight.w700)),
                const SizedBox(height: 12),
                _buildModernDropdown(
                  value: _boundaryStatus,
                  items: const ['Matches recorded area', 'Exceeds recorded area', 'Below recorded area'],
                  onChanged: (v) => setState(() => _boundaryStatus = v!), // State logic preserved[cite: 4]
                ),
                
                const SizedBox(height: 24),

                Text('Land-use consistency', style: AppText.body(14, c: AppColors.textDark, w: FontWeight.w700)),
                const SizedBox(height: 12),
                _buildModernDropdown(
                  value: _landUseStatus,
                  items: const ['Consistent with zoning', 'Inconsistent with zoning', 'Needs further review'],
                  onChanged: (v) => setState(() => _landUseStatus = v!), // State logic preserved[cite: 4]
                ),
                
                const SizedBox(height: 32),

                // Photo Section[cite: 4]
                Text('Site Photos', style: AppText.body(14, c: AppColors.textDark, w: FontWeight.w700)),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      // Render captured photos[cite: 4]
                      ..._photos.take(2).map((p) => Container(
                        width: 80, height: 80,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
                          image: DecorationImage(image: FileImage(File(p)), fit: BoxFit.cover),
                        ),
                      )),
                      // Render placeholders if empty[cite: 4]
                      if (_photos.isEmpty) ...[
                        _photoPlaceholder(),
                        const SizedBox(width: 12),
                        _photoPlaceholder(),
                        const SizedBox(width: 12),
                      ],
                      // Add Photo Button[cite: 4]
                      GestureDetector(
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const CapturePhotoScreen()),
                          );
                          // Exact original condition preserved[cite: 4]
                          if (result != null && result is Map && result['photoPath'] != null) {
                            setState(() => _photos.add(result['photoPath'] as String));
                          }
                        },
                        child: Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: const Icon(Icons.add_a_photo_rounded, color: AppColors.headerAccent),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),

                // Offline sync notice
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off_rounded, color: Color(0xFFD97706), size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Saved locally. Will sync to iMAPS intranet when connection returns.',
                          style: AppText.body(13, c: const Color(0xFFB45309), w: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),

                // Action Button[cite: 4]
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Parcel marked complete (local).')), // Original logic[cite: 4]
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.headerAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text('Mark parcel complete', style: AppText.body(15, c: Colors.white, w: FontWeight.w700)),
                      ],
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

  Widget _photoPlaceholder() {
    return Container(
      width: 80, height: 80,
      decoration: BoxDecoration(
        color: AppColors.bgLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Icon(Icons.image_outlined, color: AppColors.textSecondary),
    );
  }

  Widget _buildModernDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [BoxShadow(color: AppColors.headerDark.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
          dropdownColor: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          style: AppText.body(15, c: AppColors.textDark, w: FontWeight.w600),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}