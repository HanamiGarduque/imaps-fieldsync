import 'dart:async';

import 'package:geolocator/geolocator.dart';

class LocationService {
  static Future<void> _ensureReady() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable GPS.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission permanently denied. Please enable it in device settings.',
      );
    }
  }

  /// [timeout] bounds the wait for a first fix (opted into by Step 2). The
  /// same limit is handed to the native settings and enforced Dart-side so a
  /// non-responsive platform cannot hang the caller.
  static Future<Position> getCurrentLocation({Duration? timeout}) async {
    await _ensureReady();
    final request = Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeout,
      ),
    );
    return timeout == null ? request : request.timeout(timeout);
  }


  /// Live position updates, gated on permission/service readiness.
  ///
  /// Forward errors explicitly so cancel-on-error listeners can recover
  /// without waiting on the native subscription's asynchronous cancellation.
  static Stream<Position> getPositionStream({int distanceFilter = 4}) {
    late StreamController<Position> controller;
    StreamSubscription<Position>? sub;
    var cancelled = false;
    controller = StreamController<Position>(
      onListen: () async {
        try {
          await _ensureReady();
          // The listener may cancel while the readiness gate awaits.
          if (cancelled) return;
          sub = Geolocator.getPositionStream(
            locationSettings: LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: distanceFilter,
            ),
          ).listen(
            controller.add,
            onError: (Object e, StackTrace s) => controller.addError(e, s),
            onDone: () => controller.close(),
          );
        } catch (e, s) {
          if (cancelled) return;
          controller.addError(e, s);
          controller.close();
        }
      },
      onCancel: () {
        cancelled = true;
        sub?.cancel();
      },
    );
    return controller.stream;
  }
}
