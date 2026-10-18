import 'package:flutter/widgets.dart';

import 'screen_protection_service.dart';

/// Observes types/opacity/animation, never route names. Attach an instance to
/// each Navigator; nested observers inherit the visibility of their parent route.
class ScreenProtectionObserver extends NavigatorObserver {
  ScreenProtectionObserver(this.protection);
  final ScreenProtectionService protection;
  final _routes = <Route<dynamic>>[];
  final _departing = <Route<dynamic>>{};
  final _arriving = <Route<dynamic>>{};
  final _listeners = <TransitionRoute<dynamic>, AnimationStatusListener>{};

  void _watch(Route<dynamic> route) {
    if (route is! TransitionRoute<dynamic> || _listeners.containsKey(route)) {
      return;
    }
    void changed(AnimationStatus status) {
      if (status == AnimationStatus.dismissed && _departing.remove(route)) {
        _unwatch(route);
      }
      _publish();
    }

    _listeners[route] = changed;
    route.animation?.addStatusListener(changed);
  }

  void _unwatch(Route<dynamic> route) {
    if (route is! TransitionRoute<dynamic>) return;
    final listener = _listeners.remove(route);
    if (listener != null) route.animation?.removeStatusListener(listener);
  }

  void _publish() {
    final visible = <Route<dynamic>>{};
    var transitioning = _departing.isNotEmpty || _arriving.isNotEmpty;
    for (final route in _routes.reversed) {
      visible.add(route);
      final settled =
          !_arriving.contains(route) &&
          (route is! TransitionRoute<dynamic> ||
              route.animation?.status == AnimationStatus.completed);
      transitioning |= !settled;
      if (route is TransitionRoute<dynamic> && route.opaque && settled) break;
    }
    visible.addAll(_departing);
    protection.updateNavigation(
      this,
      known: {..._routes, ..._departing},
      visible: visible,
      parent: navigator == null ? null : ModalRoute.of(navigator!.context),
      transitioning: transitioning,
      popup: visible.any((route) => route is PopupRoute<dynamic>),
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _arriving.add(route);
    _watch(route);
    _publish();
    // A route can initially expose a completed proxy animation BEFORE its
    // push animation starts. Keep the outgoing policy through the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _arriving.remove(route);
      if (navigator != null) _publish();
    });
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _arriving.remove(route);
    if (route is TransitionRoute<dynamic> &&
        route.animation?.status != AnimationStatus.dismissed) {
      _departing.add(route);
      _watch(route);
    } else {
      _unwatch(route);
    }
    _publish();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _arriving.remove(route);
    _departing.remove(route);
    _unwatch(route);
    _publish();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (oldRoute != null) {
      _routes.remove(oldRoute);
      _arriving.remove(oldRoute);
      _unwatch(oldRoute);
    }
    if (newRoute != null) {
      _routes.insert(index < 0 ? _routes.length : index, newRoute);
      _watch(newRoute);
    }
    _publish();
  }
}
