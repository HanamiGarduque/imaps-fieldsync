import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/models/user_profile.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth_startup/services/secure_prefs_service.dart';

import '../../../core/theme/insight_theme.dart';

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

  bool _isLoading = false;
  bool _isUploadingAvatar = false;
  File? _pickedAvatarFile;
  String? _currentAvatarUrl;

  @override
  void initState() {
    super.initState();

    final currentUser = SupabaseService.client.auth.currentUser;
    final userEmail = currentUser?.email ?? 'No email found';

    _nameCtrl = TextEditingController(text: widget.profile.fullName);
    _emailCtrl = TextEditingController(text: userEmail);
    _phoneCtrl = TextEditingController(text: widget.profile.phoneNumber ?? '');
    _currentAvatarUrl = widget.profile.avatarUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatarSource() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: InsightTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: const Icon(Icons.photo_camera_outlined, color: InsightTheme.blueInk),
                title: Text('Take a photo', style: InsightTheme.inter(14, w: FontWeight.w600, c: InsightTheme.ink)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
            ),
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: InsightTheme.blueInk),
                title: Text('Choose from gallery', style: InsightTheme.inter(14, w: FontWeight.w600, c: InsightTheme.ink)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 800);
    if (picked == null) return;

    setState(() {
      _pickedAvatarFile = File(picked.path);
      _isUploadingAvatar = true;
    });

    final uploadedUrl = await SupabaseService.uploadAvatar(
      userId: widget.profile.id,
      file: _pickedAvatarFile!,
    );

    if (uploadedUrl != null) {
      await SupabaseService.client.from('profiles').update({
        'avatar_url': uploadedUrl,
      }).eq('id', widget.profile.id);

      setState(() {
        _currentAvatarUrl = uploadedUrl;
        _isUploadingAvatar = false;
      });
      unawaited(SupabaseService.logActivity(
        eventType: 'profile_updated',
        title: 'Profile photo updated',
      ));
    } else {
      setState(() => _isUploadingAvatar = false);
      if (mounted) {
        unawaited(SupabaseService.logActivity(
          eventType: 'profile_updated',
          title: 'Profile information updated',
        ));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload photo. Please try again.')),
        );
      }
    }
  }

  /// Returns an error message if the form is invalid, or null if it's OK
  /// to submit. Kept separate from _updateProfile so the check runs before
  /// any network call and the user sees why nothing was saved.
  String? _validate() {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (name.isEmpty) return 'Full name cannot be empty.';
    if (name.length < 2) return 'Full name looks too short.';
    if (name.length > 64) return 'Full name must be 64 characters or fewer.';
    if (!RegExp(r"^[a-zA-Z\u00C0-\u017F.'\- ]+$").hasMatch(name)) {
      return 'Full name should only contain letters, spaces, and . - characters.';
    }

    if (email.isEmpty || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(email)) {
      return 'Enter a valid email address (e.g. inspector@example.com).';
    }

    // Phone is optional. Local Philippine numbers use 11 digits beginning
    // with 09; international format uses +63 followed by 10 digits.
    if (phone.isNotEmpty) {
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s-]'), '');
      final isLocalPh = RegExp(r'^09\d{9}$').hasMatch(normalizedPhone);
      final isInternationalPh = RegExp(r'^\+639\d{9}$').hasMatch(normalizedPhone);
      if (!isLocalPh && !isInternationalPh) {
        return 'Enter a valid phone number (e.g. 09171234567).';
      }
    }

    return null;
  }

  Future<void> _updateProfile() async {
    final validationError = _validate();
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validationError, style: InsightTheme.inter(13, c: Colors.white)),
          backgroundColor: const Color(0xFFE23B4E),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final updatedName = _nameCtrl.text.trim();
      final updatedPhone = _phoneCtrl.text.trim();

      await SupabaseService.client.from('profiles').update({
        'full_name': updatedName,
        'phone_number': updatedPhone,
      }).eq('id', widget.profile.id);

      final updatedProfile = UserProfile(
        id: widget.profile.id,
        fullName: updatedName,
        role: widget.profile.role,
        phoneNumber: updatedPhone,
        avatarUrl: _currentAvatarUrl,
      );
      await SecurePrefsService.setCachedProfile(updatedProfile);
      unawaited(SupabaseService.logActivity(
        eventType: 'profile_updated',
        title: 'Profile information updated',
        subtitle: 'Name and phone number updated',
      ));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile updated successfully', style: InsightTheme.inter(13, c: Colors.white)),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, updatedProfile);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: $e', style: InsightTheme.inter(13, c: Colors.white)),
            backgroundColor: const Color(0xFFE23B4E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      _GlassBackButton(onTap: () => Navigator.pop(context, null)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Edit profile', style: InsightTheme.poppins(17, w: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      Center(
                        child: GestureDetector(
                          onTap: _isUploadingAvatar ? null : _pickAvatarSource,
                          child: Container(
                            margin: const EdgeInsets.only(top: 6, bottom: 28),
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.bottomRight,
                              children: [
                                Container(
                                  width: 76,
                                  height: 76,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [InsightTheme.blue1, InsightTheme.blue2],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: ClipOval(
                                    child: _pickedAvatarFile != null
                                        ? Image.file(_pickedAvatarFile!, fit: BoxFit.cover, width: 76, height: 76)
                                        : (_currentAvatarUrl != null && _currentAvatarUrl!.isNotEmpty
                                            ? Image.network(
                                                _currentAvatarUrl!,
                                                fit: BoxFit.cover,
                                                width: 76,
                                                height: 76,
                                                errorBuilder: (context, error, stackTrace) => Center(
                                                  child: Text(initials, style: InsightTheme.poppins(22, w: FontWeight.w700, c: Colors.white)),
                                                ),
                                              )
                                            : Center(
                                                child: Text(initials, style: InsightTheme.poppins(22, w: FontWeight.w700, c: Colors.white)),
                                              )),
                                  ),
                                ),
                                if (_isUploadingAvatar)
                                  const Positioned.fill(
                                    child: CircleAvatar(
                                      backgroundColor: Colors.black38,
                                      child: SizedBox(
                                        width: 20, height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      ),
                                    ),
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
                      ),
                      _ProfileField(label: 'FULL NAME', controller: _nameCtrl, maxLength: 64),
                      _ProfileField(label: 'EMAIL', controller: _emailCtrl, isEnabled: false, maxLength: 254),
                      _ProfileField(label: 'PHONE NUMBER', controller: _phoneCtrl, maxLength: 16),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () {
                      HapticFeedback.lightImpact();
                      _updateProfile();
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ).copyWith(elevation: WidgetStateProperty.all(0)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
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
                          child: _isLoading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text('Save changes', style: InsightTheme.poppins(14.5, w: FontWeight.w600, c: Colors.white)),
                        ),
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
  final int? maxLength;

  const _ProfileField({required this.label, required this.controller, this.isEnabled = true, this.maxLength});

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
            maxLength: maxLength,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
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