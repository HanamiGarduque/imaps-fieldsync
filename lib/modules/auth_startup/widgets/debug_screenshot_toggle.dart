import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/sensitive_screen.dart';
import '../../../core/theme/insight_theme.dart';
import '../services/screen_protection_service.dart';

/// Manual debug-only setting, shown only in Security & Protection.
class DebugScreenshotToggle extends StatefulWidget {
  const DebugScreenshotToggle({super.key});

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
    final navigator = Navigator.of(context);
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
                'DEBUG ONLY. Use fictional/demo or redacted information. '
                'Screenshots stay enabled until you switch them off here, '
                'lock/sign out, restart, or leave the foreground.',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'This screen contains only fictional/demo '
                  'or redacted information.',
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
    if (!kDebugMode) return const SizedBox.shrink();
    final protection = _protection!;
    if (!protection.documentationEnabled) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: protection,
      builder: (context, _) {
        final active = protection.isDocumentationActive;
        return SwitchListTile(
          key: const ValueKey('demo-screenshot-switch'),
          title: Text('Demo screenshots',
              style: InsightTheme.inter(14, w: FontWeight.w600)),
          subtitle: Text(active
              ? 'On — screenshots allowed for this debug session. Switch off here to restore protection.'
              : 'Off — screenshot protection is on. Enable only for fictional or redacted data.',
              style: InsightTheme.inter(12.5, c: InsightTheme.ink2)),
          value: active,
          activeTrackColor: InsightTheme.blue1,
          onChanged: protection.foreground && !protection.transitioning &&
              !protection.hasPopup && (active || protection.showControl)
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
