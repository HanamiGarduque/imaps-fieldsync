import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/sensitive_screen.dart';
import '../../../core/theme/insight_theme.dart';
import '../services/screen_protection_service.dart';

/// Manual debug-only setting in Security & Protection.
class DebugScreenshotToggle extends StatefulWidget {
  const DebugScreenshotToggle({super.key, this.navigatorKey});
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<DebugScreenshotToggle> createState() => _DebugScreenshotToggleState();
}

class _DebugScreenshotToggleState extends State<DebugScreenshotToggle> {
  ScreenProtectionService? _protection;
  bool _confirming = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _protection =
        ScreenProtectionScope.maybeOf(context) ??
        ScreenProtectionService.instance;
  }

  Future<void> _confirm() async {
    final protection = _protection!;
    final navigator =
        widget.navigatorKey?.currentState ?? Navigator.of(context);
    if (_confirming || !protection.showControl) return;
    _confirming = true;
    final owner = protection.visibleScope;
    int? authorizationEpoch;
    var demoOnly = false;
    final route = DialogRoute<bool>(
      context: navigator.context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Documentation screenshots'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'DEBUG ONLY. Use approved demo, redacted, or authorized '
                'documentation information. '
                'Screenshots and screen recording stay enabled until you switch '
                'them off, lock/sign out, restart, or enter the background. '
                'Brief screenshot or recorder overlays do not require '
                'a new confirmation.',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'This screen is approved for documentation capture.',
                ),
                value: demoOnly,
                onChanged: (value) => setState(() => demoOnly = value ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: demoOnly
                  ? () {
                      authorizationEpoch = protection.securityEpoch;
                      Navigator.pop(context, true);
                    }
                  : null,
              child: const Text('Enable demo screenshots'),
            ),
          ],
        ),
      ),
    );
    try {
      final accepted = await navigator.push(route);
      await route.completed;
      if (mounted &&
          accepted == true &&
          authorizationEpoch == protection.securityEpoch &&
          identical(owner, protection.visibleScope)) {
        await protection.beginDocumentation();
        // Recheck: the demo identity/permission can be revoked while the
        // confirmation dialog was up.
        if (!protection.documentationEnabled) protection.endDocumentation();
      }
    } finally {
      _confirming = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const SizedBox.shrink();
    }
    final protection = _protection!;
    return ListenableBuilder(
      listenable: protection,
      builder: (context, _) {
        final active = protection.isDocumentationActive;
        return SwitchListTile(
          key: const ValueKey('demo-screenshot-switch'),
          title: Text(
            'Demo Screenshots',
            style: InsightTheme.inter(14, w: FontWeight.w600),
          ),
          subtitle: Text(
            'Allow screenshots and screen recording for authorized '
            'documentation using fictional demo data only.',
            style: InsightTheme.inter(12.5, c: InsightTheme.ink2),
          ),
          value: active,
          activeTrackColor: InsightTheme.blue1,
          onChanged:
              protection.foreground &&
                  !protection.transitioning &&
                  !protection.hasPopup &&
                  (active || protection.showControl)
              ? (value) {
                  if (value) {
                    _confirm();
                  } else {
                    protection.endDocumentation();
                  }
                }
              : null,
        );
      },
    );
  }
}
