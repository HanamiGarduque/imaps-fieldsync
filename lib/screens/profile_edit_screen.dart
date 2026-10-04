import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';

import '../theme/insight_theme.dart';

/// ==================================================================
/// SCREEN 18 — PROFILE EDIT
/// ==================================================================
class ProfileEditScreen extends StatefulWidget {
  final UserProfile profile;
  
  const ProfileEditScreen({super.key, required this.profile});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _regionCtrl;
  late TextEditingController _idCtrl;

  @override
  void initState() {
    super.initState();
    // Pre-filled with data matching the prototype design
    _nameCtrl = TextEditingController(text: 'Juan Reyes');
    _emailCtrl = TextEditingController(text: 'j.reyes@zoning.gov.ph');
    _phoneCtrl = TextEditingController(text: '+63 917 123 4567');
    _regionCtrl = TextEditingController(text: 'Region IV-A · Zone 3');
    _idCtrl = TextEditingController(text: 'INSP-0245');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _regionCtrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return "JR";
    List<String> parts = name.trim().split(' ');
    if (parts.length > 1) {
      return "${parts[0][0]}${parts[1][0]}".toUpperCase();
    }
    return parts[0].substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    final initials = _getInitials(_nameCtrl.text);

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      body: Stack(
        children: [
          // ----------------------------------------------------
          // BACKGROUND GRADIENT BLOBS
          // ----------------------------------------------------
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

          // ----------------------------------------------------
          // MAIN CONTENT
          // ----------------------------------------------------
          SafeArea(
            child: Column(
              children: [
                // TOP BAR
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      _GlassBackButton(onTap: () => Navigator.pop(context)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Edit profile', style: InsightTheme.poppins(17, w: FontWeight.w700)),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Text('Save', style: InsightTheme.inter(13.5, w: FontWeight.w600, c: InsightTheme.blueInk)),
                      ),
                    ],
                  ),
                ),

                // SCROLLABLE FORM
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      // AVATAR WITH EDIT BADGE
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 6, bottom: 28),
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.bottomRight,
                            children: [
                              Container(
                                width: 76, height: 76,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [InsightTheme.blue1, InsightTheme.blue2],
                                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(initials, style: InsightTheme.poppins(22, w: FontWeight.w700, c: Colors.white)),
                              ),
                              Positioned(
                                bottom: -4, right: -4,
                                child: Container(
                                  width: 28, height: 28,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: InsightTheme.bg, width: 2.5),
                                    gradient: const LinearGradient(
                                      colors: [InsightTheme.blue1, InsightTheme.blue2],
                                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: const Icon(Icons.edit_outlined, color: Colors.white, size: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // INPUT FIELDS
                      _ProfileField(label: 'FULL NAME', controller: _nameCtrl),
                      _ProfileField(label: 'EMAIL', controller: _emailCtrl),
                      _ProfileField(label: 'PHONE NUMBER', controller: _phoneCtrl),
                      _ProfileField(label: 'REGION / ZONE ASSIGNED', controller: _regionCtrl),
                      _ProfileField(label: 'INSPECTOR ID', controller: _idCtrl, isEnabled: false),
                    ],
                  ),
                ),

                // BOTTOM ACTION BUTTON
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: ElevatedButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    },
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
                        boxShadow: [
                          BoxShadow(color: InsightTheme.blue1.withOpacity(0.32), blurRadius: 22, offset: const Offset(0, 10)),
                        ],
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        constraints: const BoxConstraints(minHeight: 50),
                        child: Text('Save changes', style: InsightTheme.poppins(14.5, w: FontWeight.w600, c: Colors.white)),
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
}

/// ==================================================================
/// COMPONENT WIDGETS
/// ==================================================================

class _ProfileField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool isEnabled;

  const _ProfileField({required this.label, required this.controller, this.isEnabled = true});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: InsightTheme.jetBrains(10, w: FontWeight.w500, ls: 0.6)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            enabled: isEnabled,
            style: InsightTheme.inter(13.5, w: FontWeight.w500, c: isEnabled ? InsightTheme.ink : InsightTheme.ink3),
            decoration: InputDecoration(
              filled: true,
              fillColor: isEnabled ? InsightTheme.surface : InsightTheme.surface2,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: InsightTheme.lineStrong, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: InsightTheme.lineStrong, width: 1.5),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: InsightTheme.lineStrong, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: InsightTheme.blue1, width: 1.5),
              ),
            ),
          ),
        ],
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
        width: 38, height: 38,
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