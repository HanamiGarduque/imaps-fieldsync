import 'package:flutter/material.dart';

import '../../../core/models/user_profile.dart';
import '../services/biometric_service.dart';
import '../services/secure_prefs_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../../../core/widgets/sensitive_screen.dart';
import '../../../core/theme/insight_theme.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/widgets/field_form_widgets.dart';
import '../../../core/widgets/app_feedback.dart';
import '../widgets/debug_screenshot_toggle.dart';

typedef _Colors = InsightTheme;


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
  bool _bioConfirmed = false;
  bool _requireOnOpen = false;
  int _autoLockMins = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final supported = await BiometricService.isAvailable();
    final label = await BiometricService.primaryBiometricLabel();
    final enrolled = await BiometricService.isEnrolled();
    final confirmed = await BiometricService.isConfirmed();
    final reqOpen = await SecurePrefsService.getBioRequireOnOpen();
    final autoLock = await SecurePrefsService.getBioAutoLockMins();

    if (!mounted) return;

    setState(() {
      _deviceSupported = supported;
      _biometricLabel = label;
      _bioEnrolled = enrolled;
      _bioConfirmed = confirmed;
      _requireOnOpen = reqOpen;
      _autoLockMins = autoLock;
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
          _bioConfirmed = false;
          _requireOnOpen = true;
        });
        await SupabaseService.logActivity(
          eventType: 'security_updated',
          title: 'Biometric login enabled',
        );
        _showFeedback('$_biometricLabel login enabled successfully');
      } else {
        _showFeedback('Authentication failed. Biometric login not enabled.', success: false);
      }
    } else {
      // Disable biometric
      await BiometricService.clearEnrollment();
      setState(() {
        _bioEnrolled = false;
        _requireOnOpen = false;
      });
      await SupabaseService.logActivity(
        eventType: 'security_updated',
        title: 'Biometric login disabled',
      );
      _showFeedback('$_biometricLabel login disabled');
    }
  }

  Future<void> _testBiometric() async {
    final ok = await BiometricService.authenticate(
      reason: 'Testing biometric authentication',
    );
    if (ok) {
      _showFeedback('Biometric scan verified successfully! ✨');
    } else {
      _showFeedback('Biometric scan failed or canceled.', success: false);
    }
  }

  void _showFeedback(String msg, {bool success = true}) {
    if (!mounted) return;
    AppFeedback.show(
      context,
      message: msg,
      color: success ? InsightTheme.greenInk : InsightTheme.amberInk,
      icon: success ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SensitiveScreen(child: Scaffold(
      backgroundColor: _Colors.bg,
      body: SafeArea(child: ConstrainedContent(child: Column(children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: FieldPageHeader(title: 'Security & Protection'),
        ),
        Expanded(child: _loading
          ? const Center(child: ImapsLoadingIndicator(size: 50))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                // Section 1: Device Status Header Card
                _buildStatusCard(),

                if (ScreenProtectionScope.maybeOf(context)?.documentationEnabled ??
                    false) ...[
                  const SizedBox(height: 20),
                  _sectionHeader('DEBUG DOCUMENTATION'),
                  const SizedBox(height: 8),
                  _card([const DebugScreenshotToggle()]),
                ],

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
                      style: InsightTheme.inter(
                        14,
                        w: FontWeight.w600,
                        c: _Colors.ink,
                      ),
                    ),
                    subtitle: Text(
                      _deviceSupported
                          ? (_bioEnrolled
                              ? (_bioConfirmed
                                  ? 'Active (Uses phone system $_biometricLabel)'
                                  : 'Enrolled — log in with your password once to activate')
                              : 'Uses your phone OS registered $_biometricLabel')
                          : 'Hardware not available or biometrics not enrolled in phone OS Settings',
                      style: InsightTheme.inter(12.5, c: _Colors.ink2),
                    ),
                  ),

                  if (_bioEnrolled && !_bioConfirmed) ...[
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 18, color: InsightTheme.amberInk),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'One more step: sign in with your email and passcode once. '
                              '$_biometricLabel unlock won\'t be offered anywhere until that '
                              'confirms it\'s really you.',
                              style: InsightTheme.inter(12, c: InsightTheme.amberInk, h: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (_bioEnrolled) ...[
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      title: Text('Test / Re-verify Sensor', style: InsightTheme.inter(14, w: FontWeight.w600, c: _Colors.ink)),
                      subtitle: Text('Scan fingerprint / face to verify hardware response', style: InsightTheme.inter(12, c: _Colors.ink2)),
                      trailing: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(60, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          side: const BorderSide(color: InsightTheme.lineStrong),
                          shape: RoundedRectangleBorder(borderRadius: InsightTheme.roundedSm),
                        ),
                        onPressed: _testBiometric,
                        child: Text('Test Scan', style: InsightTheme.inter(13, w: FontWeight.w700, c: _Colors.blue1)),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      value: _requireOnOpen,
                      onChanged: (v) async {
                        await SecurePrefsService.setBioRequireOnOpen(v);
                        setState(() => _requireOnOpen = v);
                        await SupabaseService.logActivity(
                          eventType: 'security_updated',
                          title: 'App opening protection updated',
                          subtitle: v ? 'Biometric required on app opening' : 'Biometric not required on app opening',
                        );
                      },
                      activeTrackColor: _Colors.blue1,
                      title: Text(
                        'Require When Opening App',
                        style: InsightTheme.inter(
                          14,
                          w: FontWeight.w600,
                          c: _Colors.ink,
                        ),
                      ),
                      subtitle: Text(
                        'Prompt biometric verification on app launch',
                        style: InsightTheme.inter(12, c: _Colors.ink2),
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
                        style: InsightTheme.inter(
                          14,
                          w: FontWeight.w600,
                          c: _Colors.ink,
                        ),
                      ),
                      subtitle: Text(
                        'Lock app after period in background or idle',
                        style: InsightTheme.inter(12, c: _Colors.ink2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
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

                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.security_rounded, size: 18, color: _Colors.ink3),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Biometric credentials are managed by your device\'s secure hardware (Keystore/Secure Enclave) and never transmitted to external servers — iMAPS FieldSync never sees or stores them.',
                        style: InsightTheme.inter(12, c: _Colors.ink3, h: 1.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            )),
      ]))),
    ));
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _bioEnrolled ? _Colors.blueTint : _Colors.surface2,
        borderRadius: InsightTheme.roundedMd,
        border: Border.all(color: _bioEnrolled ? _Colors.blue1.withValues(alpha: 0.18) : _Colors.line),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _Colors.surface,
              borderRadius: InsightTheme.roundedSm,
            ),
            child: Icon(
              _bioEnrolled ? Icons.verified_user_rounded : Icons.shield_outlined,
              color: _Colors.blueInk,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  !_bioEnrolled ? 'Protection Disabled'
                      : _bioConfirmed ? '$_biometricLabel Active'
                      : '$_biometricLabel Pending Activation',
                  style: InsightTheme.urbanist(
                    16,
                    w: FontWeight.w700,
                    c: _Colors.blueInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _bioEnrolled
                      ? 'Keystore Protected · App opening protection ${_requireOnOpen ? "on" : "off"}'
                      : 'Toggle switch below to register $_biometricLabel',
                  style: InsightTheme.inter(
                    12,
                    c: _Colors.ink2,
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
      style: InsightTheme.inter(
        12,
        w: FontWeight.w700,
        c: _Colors.ink3,
        ls: 0.6,
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Material(
      color: _Colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: InsightTheme.roundedMd,
        side: const BorderSide(color: _Colors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTileTheme(
        data: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16),
          minVerticalPadding: 8,
          minTileHeight: 64,
          horizontalTitleGap: 12,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  Widget _lockChip(String label, int mins) {
    final selected = _autoLockMins == mins;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: _Colors.blue1,
      backgroundColor: _Colors.surface,
      side: BorderSide(color: selected ? _Colors.blue1 : _Colors.lineStrong),
      shape: RoundedRectangleBorder(borderRadius: InsightTheme.roundedSm),
      labelStyle: InsightTheme.inter(
        12.5,
        w: FontWeight.w600,
        c: selected ? Colors.white : _Colors.ink2,
      ),
      onSelected: (val) async {
        if (val) {
          await SecurePrefsService.setBioAutoLockMins(mins);
          setState(() => _autoLockMins = mins);
          await SupabaseService.logActivity(
            eventType: 'security_updated',
            title: 'Auto-lock period updated',
            subtitle: label,
          );
        }
      },
    );
  }
}
