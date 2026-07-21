import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';
import '../services/biometric_service.dart';
import '../services/secure_prefs_service.dart';
import '../services/quick_unlock_service.dart';
import '../widgets/imaps_loading_indicator.dart';
import 'quick_unlock_setup_screen.dart';

class _Colors {
  static const bg = Color(0xFFF2F4FB);
  static const surface = Colors.white;
  static const ink = Color(0xFF12141F);
  static const ink2 = Color(0xFF666C82);
  static const ink3 = Color(0xFFA2A7BC);
  static const blue1 = Color(0xFF3D6BFF);
  static const blue2 = Color(0xFF0B2FBF);
  static const line = Color(0x12141628);
}


class SecuritySettingsScreen extends StatefulWidget {
  final UserProfile profile;
  const SecuritySettingsScreen({super.key, required this.profile});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  bool _loading = true;
  bool _deviceSupported = false;
  String _biometricLabel = 'Biometric';

  // Toggles
  bool _bioEnrolled = false;
  bool _requireOnOpen = false;
  bool _requireOnSync = false;
  bool _requireProfile = false;
  int _autoLockMins = 0;

  // Pattern unlock
  bool _patternEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final supported = await BiometricService.isAvailable();
    final label = await BiometricService.primaryBiometricLabel();
    final enrolled = await BiometricService.isEnrolled();
    final reqOpen = await SecurePrefsService.getBioRequireOnOpen();
    final reqSync = await SecurePrefsService.getBioRequireOnSync();
    final reqProf = await SecurePrefsService.getBioRequireProfile();
    final autoLock = await SecurePrefsService.getBioAutoLockMins();
    final patEnabled = await QuickUnlockService.isPatternEnabled();

    if (!mounted) return;

    setState(() {
      _deviceSupported = supported;
      _biometricLabel = label;
      _bioEnrolled = enrolled;
      _requireOnOpen = reqOpen;
      _requireOnSync = reqSync;
      _requireProfile = reqProf;
      _autoLockMins = autoLock;
      _patternEnabled = patEnabled;
      _loading = false;
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      // Prompt biometric authentication to enroll
      final ok = await BiometricService.authenticate(
        reason: 'Authenticate to enable $_biometricLabel login',
      );
      if (ok) {
        await BiometricService.enroll();
        await SecurePrefsService.setBioRequireOnOpen(true);
        setState(() {
          _bioEnrolled = true;
          _requireOnOpen = true;
        });
        _showSnack('$_biometricLabel login enabled successfully');
      } else {
        _showSnack('Authentication failed. Biometric login not enabled.');
      }
    } else {
      // Disable biometric
      await BiometricService.clearEnrollment();
      setState(() {
        _bioEnrolled = false;
        _requireOnOpen = false;
        _requireOnSync = false;
        _requireProfile = false;
      });
      _showSnack('$_biometricLabel login disabled');
    }
  }

  Future<void> _testBiometric() async {
    final ok = await BiometricService.authenticate(
      reason: 'Testing biometric authentication',
    );
    if (ok) {
      _showSnack('Biometric scan verified successfully! ✨');
    } else {
      _showSnack('Biometric scan failed or canceled.');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: _Colors.ink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Colors.bg,
      appBar: AppBar(
        backgroundColor: _Colors.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Security & Protection',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _Colors.ink,
          ),
        ),
        iconTheme: const IconThemeData(color: _Colors.ink),
      ),
      body: _loading
          ? const Center(child: ImapsLoadingIndicator(size: 50))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // Section 1: Device Status Header Card
                _buildStatusCard(),

                const SizedBox(height: 20),
                _sectionHeader('BIOMETRIC & DEVICE SECURITY'),
                const SizedBox(height: 8),

                _card([
                  SwitchListTile(
                    value: _bioEnrolled,
                    onChanged: _deviceSupported ? _toggleBiometric : null,
                    activeTrackColor: _Colors.blue1,
                    title: Text(
                      'Enable $_biometricLabel Login',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _Colors.ink,
                      ),
                    ),
                    subtitle: Text(
                      _deviceSupported
                          ? (_bioEnrolled
                              ? 'Active (Uses phone system $_biometricLabel)'
                              : 'Uses your phone OS registered $_biometricLabel')
                          : 'Hardware not available or biometrics not enrolled in phone OS Settings',
                      style: GoogleFonts.inter(fontSize: 12, color: _Colors.ink2),
                    ),
                  ),

                  if (_bioEnrolled) ...[
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.fingerprint, color: _Colors.blue1),
                      title: Text('Test / Re-verify Sensor', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w500)),
                      subtitle: Text('Scan fingerprint / face to verify hardware response', style: GoogleFonts.inter(fontSize: 11.5, color: _Colors.ink2)),
                      trailing: TextButton(
                        onPressed: _testBiometric,
                        child: Text('Test Scan', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: _Colors.blue1)),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      value: _requireOnOpen,
                      onChanged: (v) async {
                        await SecurePrefsService.setBioRequireOnOpen(v);
                        setState(() => _requireOnOpen = v);
                      },
                      activeTrackColor: _Colors.blue1,
                      title: Text(
                        'Require When Opening App',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: _Colors.ink,
                        ),
                      ),
                      subtitle: Text(
                        'Prompt biometric verification on app launch',
                        style: GoogleFonts.inter(fontSize: 11.5, color: _Colors.ink2),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      value: _requireOnSync,
                      onChanged: (v) async {
                        await SecurePrefsService.setBioRequireOnSync(v);
                        setState(() => _requireOnSync = v);
                      },
                      activeTrackColor: _Colors.blue1,
                      title: Text(
                        'Require Before Syncing',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: _Colors.ink,
                        ),
                      ),
                      subtitle: Text(
                        'Confirm identity before uploading inspection data',
                        style: GoogleFonts.inter(fontSize: 11.5, color: _Colors.ink2),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      value: _requireProfile,
                      onChanged: (v) async {
                        await SecurePrefsService.setBioRequireProfile(v);
                        setState(() => _requireProfile = v);
                      },
                      activeTrackColor: _Colors.blue1,
                      title: Text(
                        'Require Before Profile Changes',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: _Colors.ink,
                        ),
                      ),
                      subtitle: Text(
                        'Confirm identity before editing personal details',
                        style: GoogleFonts.inter(fontSize: 11.5, color: _Colors.ink2),
                      ),
                    ),
                  ],
                ]),

                if (_bioEnrolled) ...[
                  const SizedBox(height: 20),
                  _sectionHeader('AUTOMATIC LOCK'),
                  const SizedBox(height: 8),

                  _card([
                    ListTile(
                      title: Text(
                        'Auto-Lock Inactivity Period',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _Colors.ink,
                        ),
                      ),
                      subtitle: Text(
                        'Lock app after period in background or idle',
                        style: GoogleFonts.inter(fontSize: 12, color: _Colors.ink2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          _lockChip('Immediately', -1),
                          _lockChip('1 Minute', 1),
                          _lockChip('5 Minutes', 5),
                          _lockChip('10 Minutes', 10),
                          _lockChip('Never', 0),
                        ],
                      ),
                    ),
                  ]),
                ],

                const SizedBox(height: 20),
                _sectionHeader('GESTURE PATTERN LOCK'),
                const SizedBox(height: 8),

                _card([
                  ListTile(
                    leading: const Icon(Icons.pattern_rounded, color: _Colors.blue1),
                    title: Text(
                      'Draw Pattern Lock',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _patternEnabled ? 'Pattern registered on device' : 'Draw a 9-dot gesture pattern for quick unlock',
                      style: GoogleFonts.inter(fontSize: 12, color: _Colors.ink2),
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => QuickUnlockSetupScreen(userEmail: widget.profile.email ?? ''),
                          ),
                        );
                        _loadSettings();
                      },
                      child: Text(_patternEnabled ? 'Change' : 'Set Up Pattern'),
                    ),
                  ),
                ]),

                const SizedBox(height: 24),
                Row(
                  children: [
                    const Icon(Icons.security_rounded, size: 16, color: _Colors.ink3),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Biometric credentials and pattern hashes are stored in the device Keystore. Credentials are never transmitted to external servers.',
                        style: GoogleFonts.inter(fontSize: 11.5, color: _Colors.ink3, height: 1.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _bioEnrolled
              ? [_Colors.blue1, _Colors.blue2]
              : [const Color(0xFF1E293B), const Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _bioEnrolled ? Icons.verified_user_rounded : Icons.shield_outlined,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _bioEnrolled ? '$_biometricLabel Active' : 'Protection Disabled',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _bioEnrolled
                      ? 'Keystore Protected · ${_requireOnOpen ? "Auto-Lock On" : "Standard"}'
                      : 'Toggle switch below to register $_biometricLabel',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Text(
      text,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: _Colors.ink3,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: _Colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Colors.line),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _lockChip(String label, int mins) {
    final selected = _autoLockMins == mins;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: _Colors.blue1,
      labelStyle: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: selected ? Colors.white : _Colors.ink2,
      ),
      onSelected: (val) async {
        if (val) {
          await SecurePrefsService.setBioAutoLockMins(mins);
          setState(() => _autoLockMins = mins);
        }
      },
    );
  }
}
