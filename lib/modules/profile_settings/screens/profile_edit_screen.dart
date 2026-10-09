import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/models/user_profile.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth_startup/services/secure_prefs_service.dart';

import '../../../core/theme/insight_theme.dart';
import '../../../core/widgets/field_form_widgets.dart';

/// Preserve internal spaces and the existing supported name characters.
String normalizeProfileFullName(String value) => value.trim();

String? validateProfileFullName(String value) {
  final name = normalizeProfileFullName(value);
  if (name.isEmpty) return 'Full name cannot be empty.';
  if (name.length < 2) return 'Full name looks too short.';
  if (name.length > 64) return 'Full name must be 64 characters or fewer.';
  if (!RegExp(r"^[a-zA-Z\u00C0-\u017F.'\- ]+$").hasMatch(name)) {
    return 'Full name should only contain letters, spaces, and . - characters.';
  }
  return null;
}

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
                leading: const Icon(
                  Icons.photo_camera_outlined,
                  color: InsightTheme.blueInk,
                ),
                title: Text(
                  'Take a photo',
                  style: InsightTheme.inter(
                    14,
                    w: FontWeight.w600,
                    c: InsightTheme.ink,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
            ),
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: InsightTheme.blueInk,
                ),
                title: Text(
                  'Choose from gallery',
                  style: InsightTheme.inter(
                    14,
                    w: FontWeight.w600,
                    c: InsightTheme.ink,
                  ),
                ),
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
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 800,
    );
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
      await SupabaseService.client
          .from('profiles')
          .update({'avatar_url': uploadedUrl})
          .eq('id', widget.profile.id);

      setState(() {
        _currentAvatarUrl = uploadedUrl;
        _isUploadingAvatar = false;
      });
      unawaited(
        SupabaseService.logActivity(
          eventType: 'profile_updated',
          title: 'Profile photo updated',
        ),
      );
    } else {
      setState(() => _isUploadingAvatar = false);
      if (mounted) {
        unawaited(
          SupabaseService.logActivity(
            eventType: 'profile_updated',
            title: 'Profile information updated',
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to upload photo. Please try again.'),
          ),
        );
      }
    }
  }

  /// Returns an error message if the form is invalid, or null if it's OK
  /// to submit. Kept separate from _updateProfile so the check runs before
  /// any network call and the user sees why nothing was saved.
  String? _validate() {
    final nameError = validateProfileFullName(_nameCtrl.text);
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (nameError != null) return nameError;

    if (email.isEmpty ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(email)) {
      return 'Enter a valid email address (e.g. inspector@example.com).';
    }

    // Phone is optional. Local Philippine numbers use 11 digits beginning
    // with 09; international format uses +63 followed by 10 digits.
    if (phone.isNotEmpty) {
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s-]'), '');
      final isLocalPh = RegExp(r'^09\d{9}$').hasMatch(normalizedPhone);
      final isInternationalPh = RegExp(
        r'^\+639\d{9}$',
      ).hasMatch(normalizedPhone);
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
          content: Text(
            validationError,
            style: InsightTheme.inter(13, c: Colors.white),
          ),
          backgroundColor: const Color(0xFFE23B4E),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final updatedName = normalizeProfileFullName(_nameCtrl.text);
      final updatedPhone = _phoneCtrl.text.trim();

      await SupabaseService.client
          .from('profiles')
          .update({'full_name': updatedName, 'phone_number': updatedPhone})
          .eq('id', widget.profile.id);

      final updatedProfile = UserProfile(
        id: widget.profile.id,
        fullName: updatedName,
        role: widget.profile.role,
        phoneNumber: updatedPhone,
        avatarUrl: _currentAvatarUrl,
      );
      await SecurePrefsService.setCachedProfile(updatedProfile);
      unawaited(
        SupabaseService.logActivity(
          eventType: 'profile_updated',
          title: 'Profile information updated',
          subtitle: 'Name and phone number updated',
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Profile updated successfully',
              style: InsightTheme.inter(13, c: Colors.white),
            ),
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
            content: Text(
              'Failed to update profile: $e',
              style: InsightTheme.inter(13, c: Colors.white),
            ),
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

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    final initials = UserProfile.avatarInitials(_nameCtrl.text);

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      body: FieldFormBody(
        header: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.pop(context, null),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                style: IconButton.styleFrom(
                  backgroundColor: InsightTheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: InsightTheme.roundedSm,
                  ),
                ),
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 20,
                  color: InsightTheme.ink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Edit profile',
                  style: InsightTheme.urbanist(22, w: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        action: FieldPrimaryButton(
          label: 'Save changes',
          busy: _isLoading,
          busyLabel: 'Saving changes…',
          onPressed: _isLoading
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  _updateProfile();
                },
        ),
        children: [
          const FieldSectionHeading(
            title: 'Profile photo',
            hint:
                'Tap to change your photo. Photo changes are saved immediately.',
          ),
          Center(
            child: Semantics(
              button: true,
              enabled: !_isUploadingAvatar,
              label: 'Change profile photo',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(48),
                  onTap: _isUploadingAvatar ? null : _pickAvatarSource,
                  child: Container(
                    margin: const EdgeInsets.only(top: 4, bottom: 20),
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: InsightTheme.blue1,
                          ),
                          child: ClipOval(
                            child: _pickedAvatarFile != null
                                ? Image.file(
                                    _pickedAvatarFile!,
                                    fit: BoxFit.cover,
                                    width: 88,
                                    height: 88,
                                  )
                                : (_currentAvatarUrl != null &&
                                          _currentAvatarUrl!.isNotEmpty
                                      ? Image.network(
                                          _currentAvatarUrl!,
                                          fit: BoxFit.cover,
                                          width: 88,
                                          height: 88,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  Center(
                                                    child: Text(
                                                      initials,
                                                      style:
                                                          InsightTheme.poppins(
                                                            22,
                                                            w: FontWeight.w700,
                                                            c: Colors.white,
                                                          ),
                                                    ),
                                                  ),
                                        )
                                      : Center(
                                          child: Text(
                                            initials,
                                            style: InsightTheme.poppins(
                                              22,
                                              w: FontWeight.w700,
                                              c: Colors.white,
                                            ),
                                          ),
                                        )),
                          ),
                        ),
                        if (_isUploadingAvatar)
                          const Positioned.fill(
                            child: CircleAvatar(
                              backgroundColor: Colors.black38,
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: -4,
                          right: -4,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: InsightTheme.bg,
                                width: 2.5,
                              ),
                              color: InsightTheme.blue1,
                            ),
                            child: const Icon(
                              Icons.edit_outlined,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const FieldSectionHeading(
            title: 'Personal details',
            hint: 'Keep your inspector name and contact details up to date.',
          ),
          _ProfileField(
            label: 'Full name',
            controller: _nameCtrl,
            maxLength: 64,
          ),
          _ProfileField(
            label: 'Phone number',
            controller: _phoneCtrl,
            maxLength: 16,
            helper: 'Optional · e.g. 09171234567',
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 8),
          const FieldSectionHeading(
            title: 'Account',
            hint: 'Your sign-in email is read-only.',
          ),
          _ProfileField(
            label: 'Email',
            controller: _emailCtrl,
            isEnabled: false,
            maxLength: 254,
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
  final String? helper;
  final TextInputType? keyboardType;

  const _ProfileField({
    required this.label,
    required this.controller,
    this.isEnabled = true,
    this.maxLength,
    this.helper,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        enabled: isEnabled,
        maxLength: maxLength,
        keyboardType: keyboardType,
        buildCounter:
            (_, {required currentLength, required isFocused, maxLength}) =>
                null,
        style: InsightTheme.inter(
          16,
          w: FontWeight.w500,
          c: isEnabled ? InsightTheme.ink : InsightTheme.ink3,
        ),
        decoration: InsightTheme.compactFormInput.copyWith(
          labelText: label,
          helperText: helper,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          fillColor: isEnabled ? InsightTheme.surface : InsightTheme.surface2,
        ),
      ),
    );
  }
}
