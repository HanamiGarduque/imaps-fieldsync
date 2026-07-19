import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/biometric_service.dart';
import '../services/quick_unlock_service.dart';
import '../widgets/pattern_lock_pad.dart';

class _Colors {
  static const bg = Color(0xFFF2F4FB);
  static const surface = Colors.white;
  static const ink = Color(0xFF12141F);
  static const ink2 = Color(0xFF666C82);
  static const ink3 = Color(0xFFA2A7BC);
  static const blue1 = Color(0xFF3D6BFF);
  static const blue2 = Color(0xFF0B2FBF);
  static const green = Color(0xFF10B981);
  static const coral = Color(0xFFE23B4E);
  static const line = Color(0x12141628);
}

class QuickUnlockSetupScreen extends StatefulWidget {
  final String userEmail;
  const QuickUnlockSetupScreen({super.key, required this.userEmail});

  @override
  State<QuickUnlockSetupScreen> createState() => _QuickUnlockSetupScreenState();
}

class _QuickUnlockSetupScreenState extends State<QuickUnlockSetupScreen> {
  bool _loading = true;
  bool _biometricAvailable = false;
  String _biometricLabel = 'Biometric';
  bool _biometricEnabled = false;
  bool _patternEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final available = await BiometricService.isAvailable();
    final label = available ? await BiometricService.primaryBiometricLabel() : 'Biometric';
    final bioEnabled = await QuickUnlockService.isBiometricEnabled();
    final patEnabled = await QuickUnlockService.isPatternEnabled();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricLabel = label;
      _biometricEnabled = bioEnabled;
      _patternEnabled = patEnabled;
      _loading = false;
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      final ok = await BiometricService.authenticate(
        reason: 'Confirm your $_biometricLabel to enable quick unlock',
      );
      if (!ok) return;
      await QuickUnlockService.setBiometricEnabled(true, email: widget.userEmail);
    } else {
      await QuickUnlockService.disableBiometric();
    }
    setState(() => _biometricEnabled = value);
    _showSnack(value ? '$_biometricLabel unlock enabled' : '$_biometricLabel unlock turned off');
  }

  Future<void> _setupPattern() async {
    final pattern = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(builder: (_) => const _PatternSetupFlow()),
    );
    if (pattern == null) return;
    await QuickUnlockService.setPattern(pattern, email: widget.userEmail);
    setState(() => _patternEnabled = true);
    _showSnack('Pattern unlock enabled');
  }

  Future<void> _disablePattern() async {
    await QuickUnlockService.disablePattern();
    setState(() => _patternEnabled = false);
    _showSnack('Pattern unlock turned off');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500)),
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
        title: Text('Quick Unlock', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: _Colors.ink)),
        iconTheme: const IconThemeData(color: _Colors.ink),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Set up a faster way to open InSight in the field — handy when you\'re wearing gloves or the screen keyboard is inconvenient. This never replaces your MPDO account; it only unlocks this device.',
                  style: GoogleFonts.inter(fontSize: 13, color: _Colors.ink2, height: 1.5),
                ),
                const SizedBox(height: 20),

                _card([
                  _switchTile(
                    icon: _biometricLabel == 'Face'
                        ? Icons.face_retouching_natural
                        : Icons.fingerprint,
                    title: _biometricAvailable ? '$_biometricLabel Unlock' : 'Biometric Unlock',
                    subtitle: _biometricAvailable
                        ? 'Use your device\'s $_biometricLabel sensor'
                        : 'Not available on this device (no fingerprint/face enrolled)',
                    value: _biometricEnabled,
                    enabled: _biometricAvailable,
                    onChanged: _toggleBiometric,
                  ),
                ]),

                const SizedBox(height: 14),

                _card([
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: const Icon(Icons.pattern, color: _Colors.blue1),
                    title: Text('Pattern Unlock', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _Colors.ink)),
                    subtitle: Text(
                      _patternEnabled ? 'Pattern is set' : 'Draw a pattern — works great with gloves on',
                      style: GoogleFonts.inter(fontSize: 12, color: _Colors.ink2),
                    ),
                    trailing: TextButton(
                      onPressed: _patternEnabled ? _disablePattern : _setupPattern,
                      child: Text(
                        _patternEnabled ? 'Turn off' : 'Set up',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _patternEnabled ? _Colors.coral : _Colors.blue1,
                        ),
                      ),
                    ),
                  ),
                  if (_patternEnabled)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: TextButton(
                        onPressed: _setupPattern,
                        style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: EdgeInsets.zero),
                        child: Text('Change pattern', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: _Colors.ink2)),
                      ),
                    ),
                ]),

                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.shield_outlined, size: 16, color: _Colors.ink3),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You can enable both — InSight will ask for whichever is on when you open the app. Your email + passcode always still works as a fallback.',
                        style: GoogleFonts.inter(fontSize: 11.5, color: _Colors.ink3, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: _Colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _Colors.line),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      secondary: Icon(icon, color: enabled ? _Colors.blue1 : _Colors.ink3),
      title: Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: enabled ? _Colors.ink : _Colors.ink3)),
      subtitle: Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: _Colors.ink2)),
      value: value,
      activeColor: _Colors.blue1,
      onChanged: enabled ? onChanged : null,
    );
  }
}

/// Draw-twice-to-confirm flow, pushed as its own route so it can be
/// reused both for first-time setup and "change pattern".
class _PatternSetupFlow extends StatefulWidget {
  const _PatternSetupFlow();

  @override
  State<_PatternSetupFlow> createState() => _PatternSetupFlowState();
}

class _PatternSetupFlowState extends State<_PatternSetupFlow> {
  List<int>? _first;
  bool _error = false;

  void _onPattern(List<int> pattern) {
    if (_first == null) {
      setState(() {
        _first = pattern;
        _error = false;
      });
      return;
    }
    if (_listEquals(_first!, pattern)) {
      Navigator.of(context).pop(pattern);
    } else {
      setState(() {
        _first = null;
        _error = true;
      });
    }
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final title = _first == null ? 'Draw a new pattern' : 'Confirm your pattern';
    return Scaffold(
      backgroundColor: _Colors.bg,
      appBar: AppBar(
        backgroundColor: _Colors.bg,
        elevation: 0,
        title: Text('Set Pattern', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: _Colors.ink)),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          children: [
            Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: _Colors.ink)),
            const SizedBox(height: 6),
            Text(
              _error ? 'Patterns didn\'t match — try again' : 'Connect at least 4 dots',
              style: GoogleFonts.inter(fontSize: 12.5, color: _error ? _Colors.coral : _Colors.ink2),
            ),
            const SizedBox(height: 40),
            PatternLockPad(onComplete: _onPattern, showError: _error),
          ],
        ),
      ),
    );
  }
}
