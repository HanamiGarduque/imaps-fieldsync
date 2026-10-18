import 'package:flutter/material.dart';

import '../../modules/auth_startup/services/screen_protection_service.dart';

/// App-level lifecycle binding and fail-closed native-failure cover.
class ScreenProtectionHost extends StatefulWidget {
  const ScreenProtectionHost({super.key, required this.child, this.protection});
  final Widget child;
  final ScreenProtectionService? protection;

  @override
  State<ScreenProtectionHost> createState() => _ScreenProtectionHostState();
}

class _ScreenProtectionHostState extends State<ScreenProtectionHost> {
  late final protection = widget.protection ?? ScreenProtectionService.instance;

  @override
  void initState() {
    super.initState();
    protection.attach();
  }

  @override
  void dispose() {
    protection.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScreenProtectionScope(
    protection: protection,
    child: ListenableBuilder(
      listenable: protection,
      child: widget.child,
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          child!,
          if (protection.mustObscure)
            Positioned.fill(
              child: Material(
                key: const ValueKey('privacy-curtain'),
                color: const Color(0xFFF4F6FB),
                child: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shield_outlined),
                          const SizedBox(height: 16),
                          Text(
                            protection.nativeFailure
                                ? 'Screen protection unavailable. Content is hidden.'
                                : 'Protected screen',
                          ),
                          if (protection.nativeFailure)
                            TextButton(
                              onPressed: protection.retryProtection,
                              child: const Text('Retry protection'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class ScreenProtectionScope extends InheritedWidget {
  const ScreenProtectionScope({
    super.key,
    required this.protection,
    required super.child,
  });
  final ScreenProtectionService protection;
  static ScreenProtectionService? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ScreenProtectionScope>()
      ?.protection;
  @override
  bool updateShouldNotify(ScreenProtectionScope oldWidget) =>
      protection != oldWidget.protection;
}

/// Explicit visibility for retained/outgoing tab children, independent of route
/// identity. It does not disable animation tickers or change business state.
class SensitiveScreenVisibility extends InheritedWidget {
  const SensitiveScreenVisibility({
    super.key,
    required this.visible,
    required super.child,
  });
  final bool visible;
  @override
  bool updateShouldNotify(SensitiveScreenVisibility oldWidget) =>
      visible != oldWidget.visible;
}

class SensitiveScreen extends StatefulWidget {
  const SensitiveScreen({super.key, required this.child});
  final Widget child;
  @override
  State<SensitiveScreen> createState() => _SensitiveScreenState();
}

class _SensitiveScreenState extends State<SensitiveScreen> {
  ScreenProtectionService? _protection;
  bool _hosted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hosted = ScreenProtectionScope.maybeOf(context);
    final protection = hosted ?? ScreenProtectionService.instance;
    if (_protection != protection) _protection?.unregister(this);
    _protection = protection;
    _hosted = hosted != null;
    protection.register(
      this,
      ModalRoute.of(context),
      visible:
          context
              .dependOnInheritedWidgetOfExactType<SensitiveScreenVisibility>()
              ?.visible ??
          true,
    );
  }

  @override
  void dispose() {
    _protection?.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hosted) return widget.child;
    // The scope knows its policy during the first build, before the ancestor
    // host's deferred notification. Do not paint a first frame of unguarded PII.
    return ListenableBuilder(
      listenable: _protection!,
      child: widget.child,
      builder: (_, child) => Stack(
        fit: StackFit.expand,
        children: [
          child!,
          // Cover, never unmount: live camera previews, text fields and other
          // stateful content must survive an obscured window (backgrounding,
          // pending/failing native protection) without recreation.
          if (_protection!.mustObscure)
            const Positioned.fill(child: ColoredBox(color: Color(0xFFF4F6FB))),
        ],
      ),
    );
  }
}
