import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/secure_prefs_service.dart';

void main() {
  group('auto-lock behavior', () {
    test('immediately should lock on resume without grace', () {
      expect(
        SecurePrefsService.shouldLockAfterElapsed(
          minutes: -1,
          elapsed: const Duration(seconds: 1),
        ),
        isTrue,
      );
    });

    test('1 minute should permit less than one minute but lock after threshold', () {
      expect(
        SecurePrefsService.shouldLockAfterElapsed(
          minutes: 1,
          elapsed: const Duration(seconds: 30),
        ),
        isFalse,
      );
      expect(
        SecurePrefsService.shouldLockAfterElapsed(
          minutes: 1,
          elapsed: const Duration(minutes: 1, seconds: 1),
        ),
        isTrue,
      );
    });

    test('timeout mapping should match immediate, minute-based, and never settings', () {
      expect(SecurePrefsService.autoLockTimeoutForMinutes(-1), Duration.zero);
      expect(SecurePrefsService.autoLockTimeoutForMinutes(1), const Duration(minutes: 1));
      expect(SecurePrefsService.autoLockTimeoutForMinutes(5), const Duration(minutes: 5));
      expect(SecurePrefsService.autoLockTimeoutForMinutes(0), isNull);
    });

    test('never should not lock at all', () {
      expect(
        SecurePrefsService.shouldLockAfterElapsed(
          minutes: 0,
          elapsed: const Duration(days: 1),
        ),
        isFalse,
      );
    });
  });
}
