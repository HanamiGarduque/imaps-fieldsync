import 'package:flutter/material.dart';
import '../../modules/auth_startup/services/screen_protection_service.dart';

/// Wrap the widget a "sensitive" screen returns from `build()` with this to
/// block screenshots, screen recording, and the Recent-Apps preview while
/// it's on screen. Works for both StatefulWidget and StatelessWidget screens
/// since it does the enter/exit bookkeeping itself — the wrapped screen
/// doesn't need to change its own State class at all.
///
/// Example:
/// ```dart
/// @override
/// Widget build(BuildContext context) {
///   return SensitiveScreen(
///     child: Scaffold(
///       ...
///     ),
///   );
/// }
/// ```
class SensitiveScreen extends StatefulWidget {
  final Widget child;
  const SensitiveScreen({super.key, required this.child});

  @override
  State<SensitiveScreen> createState() => _SensitiveScreenState();
}

class _SensitiveScreenState extends State<SensitiveScreen> {
  @override
  void initState() {
    super.initState();
    ScreenProtectionService.enter();
  }

  @override
  void dispose() {
    ScreenProtectionService.exit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
