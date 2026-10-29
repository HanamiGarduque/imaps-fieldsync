import 'dart:async';

import 'package:flutter/services.dart';

/// Android window-flag acknowledgment, not a documentation/capture grant.
class NativeScreenProtectionAck {
  NativeScreenProtectionAck({void Function()? onWindowChanged}) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'windowChanged') throw MissingPluginException();
      // An old window's acknowledgment never confirms its replacement. This
      // event only revokes observations; it cannot grant protection or capture.
      _requestId++;
      _session = null;
      onWindowChanged?.call();
    });
  }

  static const timeout = Duration(seconds: 2);
  static const _channel = MethodChannel(
    'imaps_fieldsync/screen_protection_ack',
  );

  Future<int>? _session;
  int _requestId = 0;

  Future<void> setSecure(bool secure) async {
    final requestId = ++_requestId;
    final session = _session ??= _beginSession(requestId);
    try {
      await _setSecure(secure, requestId, session).timeout(timeout);
    } catch (_) {
      // A retry starts a protective native session. That invalidates all OFF
      // requests from the timed-out/failed session, including undelivered ones.
      if (requestId == _requestId && identical(_session, session)) {
        _session = null;
      }
      rethrow;
    }
  }

  Future<int> _beginSession(int requestId) async {
    final reply = await _channel.invokeMethod<Object?>('beginSession', {
      'requestId': requestId,
    });
    if (reply is! Map ||
        reply['success'] != true ||
        reply['requestId'] is! int ||
        reply['requestId'] != requestId ||
        reply['sessionId'] is! int ||
        (reply['sessionId'] as int) <= 0 ||
        reply['secure'] != true) {
      throw StateError('Native protective session was not acknowledged.');
    }
    return reply['sessionId'] as int;
  }

  Future<void> _setSecure(
    bool secure,
    int requestId,
    Future<int> session,
  ) async {
    bool current() => requestId == _requestId && identical(_session, session);
    final sessionId = await session;
    if (!current()) throw StateError('Superseded native protection request.');
    final reply = await _channel.invokeMethod<Object?>('setSecure', {
      'sessionId': sessionId,
      'requestId': requestId,
      'secure': secure,
    });
    if (!current() ||
        reply is! Map ||
        reply['success'] != true ||
        reply['requestId'] is! int ||
        reply['requestId'] != requestId ||
        reply['sessionId'] is! int ||
        reply['sessionId'] != sessionId ||
        reply['secure'] is! bool ||
        reply['secure'] != secure) {
      throw StateError('Native window protection was not acknowledged.');
    }
  }
}
