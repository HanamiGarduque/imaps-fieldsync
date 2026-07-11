import 'package:flutter/material.dart';
import 'tasks_screen.dart';
import 'capture_photo_screen.dart';

class ParcelDetailScreen extends StatefulWidget {
  final TaskItem task;
  const ParcelDetailScreen({super.key, required this.task});

  @override
  State<ParcelDetailScreen> createState() => _ParcelDetailScreenState();
}

class _ParcelDetailScreenState extends State<ParcelDetailScreen> {
  String _boundaryStatus = 'Matches recorded area';
  String _landUseStatus = 'Consistent with zoning';
  final List<String> _photos = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FC),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1B1140), Color(0xFF4A2FE0)],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Row(
                        children: const [
                          Icon(Icons.circle, color: Colors.greenAccent, size: 10),
                          SizedBox(width: 6),
                          Text('iMAPS-FieldSync',
                              style: TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha:0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('Offline Mode',
                            style: TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.task.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          widget.task.inspectionNo,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                children: [
                  // Map placeholder
                  Container(
                    height: 140,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A2FE0),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text(
                        'Map pinpointing parcel location',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 13.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text('Actual lot boundaries vs 300 sqm',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  const SizedBox(height: 8),
                  _buildDropdown(
                    value: _boundaryStatus,
                    items: const [
                      'Matches recorded area',
                      'Exceeds recorded area',
                      'Below recorded area',
                    ],
                    onChanged: (v) => setState(() => _boundaryStatus = v!),
                  ),
                  const SizedBox(height: 18),

                  const Text('Land-use consistency',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  const SizedBox(height: 8),
                  _buildDropdown(
                    value: _landUseStatus,
                    items: const [
                      'Consistent with zoning',
                      'Inconsistent with zoning',
                      'Needs further review',
                    ],
                    onChanged: (v) => setState(() => _landUseStatus = v!),
                  ),
                  const SizedBox(height: 18),

                  // Photo thumbnails + add button
                  Row(
                    children: [
                      ..._photos.take(2).map(
                            (p) => Container(
                              width: 64,
                              height: 64,
                              margin: const EdgeInsets.only(right: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEDEBFB),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.image, color: Color(0xFF3D2FE0)),
                            ),
                          ),
                      if (_photos.isEmpty) ...[
                        _photoPlaceholder(),
                        const SizedBox(width: 12),
                        _photoPlaceholder(),
                        const SizedBox(width: 12),
                      ],
                      GestureDetector(
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const CapturePhotoScreen()),
                          );
                          if (result == true) {
                            setState(() => _photos.add('photo'));
                          }
                        },
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0EEFA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFD8D3F5)),
                          ),
                          child: const Icon(Icons.add, color: Color(0xFF3D2FE0)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Offline sync notice
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF6DD),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFF2E1A0)),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.wifi_off, color: Color(0xFF9A7B14), size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Saved locally. Will sync to iMAPS intranet when connection returns.',
                            style: TextStyle(color: Color(0xFF9A7B14), fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Parcel marked complete (local).')),
                        );
                      },
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Mark parcel complete'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3D2FE0),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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

  Widget _photoPlaceholder() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFFEDEBFB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.image_outlined, color: Color(0xFF9186D4)),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3E0F5)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13.5))))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}