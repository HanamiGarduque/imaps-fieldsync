import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';

import '../../../core/widgets/sensitive_screen.dart';
import '../services/screen_protection_service.dart';

/// Debug-only, scoped and bounded documentation permission. No capture-event
/// listener is used: this plugin does not provide Android screenshot detection.
class DebugScreenshotToggle extends StatefulWidget {
  const DebugScreenshotToggle({
    super.key,
    required this.child,
    this.navigatorKey,
  });
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<DebugScreenshotToggle> createState() => _DebugScreenshotToggleState();
}

class _DebugScreenshotToggleState extends State<DebugScreenshotToggle> {
  ScreenProtectionService? _protection;
  bool _confirming = false;
  static final _restoreAction = CustomSemanticsAction(
    label: 'Restore screenshot protection',
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _protection =
        ScreenProtectionScope.maybeOf(context) ??
        ScreenProtectionService.instance;
  }

  @override
  void dispose() {
    _protection?.endDocumentation();
    super.dispose();
  }

  Future<void> _confirm() async {
    final protection = _protection!;
    final navigator = widget.navigatorKey?.currentState;
    if (_confirming || !protection.showControl || navigator == null) return;
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
                'DEBUG ONLY. Protection restores automatically in 20 seconds, '
                'on navigation or when the app leaves the foreground. '
                'Restore early with Ctrl+Shift+P or the screen-reader action '
                '“Restore screenshot protection”.',
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
              child: const Text('Enable for 20 seconds'),
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
        protection.beginDocumentation();
      }
    } finally {
      _confirming = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return widget.child;
    final protection = _protection!;
    return ListenableBuilder(
      listenable: protection,
      child: widget.child,
      builder: (context, child) {
        final show = protection.showControl;
        final documentation =
            protection.documentationPhase != DocumentationPhase.off;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(
              LogicalKeyboardKey.keyP,
              control: true,
              shift: true,
            ): protection.endDocumentation,
          },
          child: Focus(
            autofocus: true,
            child: Semantics(
              container: documentation,
              customSemanticsActions: documentation
                  ? {_restoreAction: protection.endDocumentation}
                  : null,
              child: Column(
                children: [
                  ClipRect(
                    child: IgnorePointer(
                      ignoring: !show,
                      child: ExcludeSemantics(
                        excluding: !show,
                        child: TweenAnimationBuilder<double>(
                          duration: ScreenProtectionService.controlFadeDuration,
                          tween: Tween(begin: 0, end: show ? 1 : 0),
                          builder: (context, value, control) {
                            if (value == 0) {
                              if (protection.documentationPhase ==
                                  DocumentationPhase.hidingControl) {
                                final generation =
                                    protection.documentationGeneration;
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted) {
                                    protection.confirmControlHidden(generation);
                                  }
                                });
                              }
                              return const SizedBox.shrink();
                            }
                            final height =
                                48 + MediaQuery.paddingOf(context).top;
                            return SizedBox(
                              height: height * value,
                              child: OverflowBox(
                                alignment: Alignment.topCenter,
                                minHeight: height,
                                maxHeight: height,
                                child: Opacity(
                                  key: const ValueKey(
                                    'documentation-control-opacity',
                                  ),
                                  opacity: value,
                                  child: control,
                                ),
                              ),
                            );
                          },
                          child: SafeArea(
                            bottom: false,
                            child: SizedBox(
                              height: 48,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: IconButton(
                                    key: const ValueKey(
                                      'documentation-control',
                                    ),
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size(48, 48),
                                      foregroundColor: Colors.black54,
                                      backgroundColor: Colors.white54,
                                    ),
                                    icon: const Icon(
                                      Icons.camera_alt_outlined,
                                      size: 18,
                                      semanticLabel:
                                          'Temporarily allow demo screenshots',
                                    ),
                                    onPressed: _confirm,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: show,
                      child: child!,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
