import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../services/auto_lock_controller.dart';

/// Root-level, non-consuming activity monitor.
///
/// Wrapped around the app's navigator by [MaterialApp.builder], so pointer,
/// keyboard and text-input activity on pushed routes count too. It never adds
/// a gesture recognizer and always returns false from the hardware-key
/// handler, so camera previews, overlays, text fields and navigation keep
/// receiving their normal input.
class AutoLockActivityHost extends StatefulWidget {
  const AutoLockActivityHost({super.key, required this.child, this.controller});

  final Widget child;
  final AutoLockController? controller;

  @override
  State<AutoLockActivityHost> createState() => _AutoLockActivityHostState();
}

class _AutoLockActivityHostState extends State<AutoLockActivityHost>
    with WidgetsBindingObserver {
  late final AutoLockController _controller =
      widget.controller ?? AutoLockController.instance;
  late final bool Function(KeyEvent) _keyHandler = _handleKeyEvent;

  EditableTextState? _editable;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_keyHandler);
    FocusManager.instance.addListener(_syncFocusedEditable);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncFocusedEditable();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_keyHandler);
    FocusManager.instance.removeListener(_syncFocusedEditable);
    _detachFocusedEditable();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _controller.recordActivity();
    }
    // Never claim the event: text fields and shortcuts still need it.
    return false;
  }

  void _syncFocusedEditable() {
    if (!mounted) return;
    EditableTextState? editable;
    final context = FocusManager.instance.primaryFocus?.context;
    if (context != null) {
      try {
        editable = context.findAncestorStateOfType<EditableTextState>();
      } catch (_) {
        editable = null;
      }
    }
    if (identical(editable, _editable)) return;

    _detachFocusedEditable();
    if (editable == null || !editable.mounted) return;

    _editable = editable;
    try {
      editable.widget.controller.addListener(_onEditableChanged);
    } catch (_) {
      _editable = null;
    }
  }

  void _detachFocusedEditable() {
    final editable = _editable;
    _editable = null;
    if (editable == null) return;
    try {
      editable.widget.controller.removeListener(_onEditableChanged);
    } catch (_) {
      // The field may already be disposed together with its route.
    }
  }

  void _onEditableChanged() => _controller.recordActivity();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.handleLifecycle(state);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _controller.recordActivity(),
      onPointerMove: (_) => _controller.recordActivity(),
      onPointerSignal: (_) => _controller.recordActivity(),
      child: widget.child,
    );
  }
}
