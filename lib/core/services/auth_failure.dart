import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

enum AuthFailure implements Exception {
  authRejected,
  networkUnavailable,
  profileUnavailable,
  sessionRestoreFailed,
  unknownPostAuth;

  String get message => switch (this) {
    authRejected => 'Invalid ID or passcode. Please try again.',
    networkUnavailable =>
      'The sign-in service could not be reached. '
          'Check your internet connection and try again.',
    profileUnavailable =>
      'Your account was signed in, but the inspector '
          'profile could not be loaded. Please contact the administrator.',
    sessionRestoreFailed =>
      'Your previous session could not be restored. '
          'Please sign in again.',
    unknownPostAuth =>
      'Sign-in could not be completed. Please try again '
          'or contact the administrator.',
  };

  static AuthFailure classify(
    Object error, {
    required AuthFailure fallback,
    bool credentialRequest = false,
  }) {
    if (error is AuthFailure) return error;
    if (isNetworkError(error)) return networkUnavailable;
    if (credentialRequest &&
        error is AuthException &&
        error.code == 'invalid_credentials') {
      return authRejected;
    }
    return fallback;
  }

  static bool isNetworkError(Object error) {
    if (error == networkUnavailable ||
        error is SocketException ||
        error is HttpException ||
        error is TimeoutException ||
        error is AuthRetryableFetchException) {
      return true;
    }
    // A typed server refusal stays authoritative even if its message contains
    // words such as "clientexception". Retryable Auth fetches were handled above.
    if (error is AuthException || error is PostgrestException) return false;
    // Preserve the existing platform/SDK fallback in one place.
    final message = error.toString().toLowerCase();
    return const [
      'socketexception',
      'failed host lookup',
      'network is unreachable',
      'connection timed out',
      'clientexception',
      'timeoutexception',
    ].any(message.contains);
  }
}
