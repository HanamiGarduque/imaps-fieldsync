import 'package:flutter/material.dart';

class GuideTargetRegistry extends ChangeNotifier {
  final Map<String, GlobalKey> _keys = {};

  BuildContext? contextFor(String id) => _keys[id]?.currentContext;

  void _register(String id, GlobalKey key) {
    if (_keys.containsKey(id) && _keys[id] != key) {
      throw FlutterError('Duplicate mounted guide target: $id');
    }
    _keys[id] = key;
    notifyListeners();
  }

  void _unregister(String id, GlobalKey key) {
    if (_keys[id] != key) return;
    _keys.remove(id);
    notifyListeners();
  }

  Rect? rectFor(String id, RenderBox host) {
    final target = contextFor(id)?.findRenderObject();
    if (!host.attached ||
        !host.hasSize ||
        target is! RenderBox ||
        !target.attached ||
        !target.hasSize) {
      return null;
    }
    RenderObject? ancestor = target;
    while (ancestor != null && ancestor != host) {
      ancestor = ancestor.parent;
    }
    if (ancestor != host) return null;
    final rect = MatrixUtils.transformRect(
      target.getTransformTo(host),
      Offset.zero & target.size,
    );
    return rect.isFinite && !rect.isEmpty ? rect : null;
  }

  @override
  void dispose() {
    _keys.clear();
    super.dispose();
  }
}

class GuideTargetScope extends InheritedWidget {
  final GuideTargetRegistry registry;

  const GuideTargetScope({
    super.key,
    required this.registry,
    required super.child,
  });

  static GuideTargetRegistry? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GuideTargetScope>()?.registry;

  @override
  bool updateShouldNotify(GuideTargetScope oldWidget) =>
      registry != oldWidget.registry;
}

/// Without a guide scope this is an inert presentation anchor.
class GuideTarget extends StatefulWidget {
  final String id;
  final Widget child;

  const GuideTarget({super.key, required this.id, required this.child});

  @override
  State<GuideTarget> createState() => _GuideTargetState();
}

class _GuideTargetState extends State<GuideTarget> {
  final _targetKey = GlobalKey();
  GuideTargetRegistry? _registry;
  String? _registeredId;

  @override
  void deactivate() {
    // A replaced page is detached before disposal at the end of the frame.
    // Its IDs must be available to the incoming page immediately.
    if (_registeredId != null) {
      _registry?._unregister(_registeredId!, _targetKey);
    }
    _registry = null;
    _registeredId = null;
    super.deactivate();
  }

  @override
  void dispose() {
    if (_registeredId != null) {
      _registry?._unregister(_registeredId!, _targetKey);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registry = GuideTargetScope.maybeOf(context);
    if (registry != _registry || widget.id != _registeredId) {
      if (_registeredId != null) {
        _registry?._unregister(_registeredId!, _targetKey);
      }
      _registry = null;
      _registeredId = null;
      // Report duplicates during build, not a partially-mounted first lifecycle.
      registry?._register(widget.id, _targetKey);
      _registry = registry;
      _registeredId = widget.id;
    }
    return KeyedSubtree(key: _targetKey, child: widget.child);
  }
}
