import 'dart:html' as html;
import 'package:flutter/foundation.dart';

class CompassHelper {
  static final ValueNotifier<double> headingNotifier = ValueNotifier<double>(0.0);
  static final ValueNotifier<bool> isListening = ValueNotifier<bool>(false);
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    _initialized = true;
    startListening();
  }

  static void requestPermissionAndStart() {
    try {
      final jsWindow = html.window as dynamic;
      final devOrient = jsWindow.DeviceOrientationEvent;
      if (devOrient != null && devOrient.requestPermission != null) {
        devOrient.requestPermission().then((permissionState) {
          if (permissionState == 'granted') {
            startListening();
          }
        }).catchError((_) {
          startListening();
        });
      } else {
        startListening();
      }
    } catch (_) {
      startListening();
    }
  }

  static void startListening() {
    try {
      html.window.onDeviceOrientation.listen((html.DeviceOrientationEvent event) {
        double? heading;
        final dynamic dynamicEvent = event;
        // iOS Safari provides webkitCompassHeading (0 = North, 90 = East, etc.)
        if (dynamicEvent.webkitCompassHeading != null) {
          heading = (dynamicEvent.webkitCompassHeading as num).toDouble();
        } else if (event.alpha != null) {
          // Android Chrome / Standard: alpha is 0 to 360 degrees
          heading = (360.0 - event.alpha!) % 360.0;
        }

        if (heading != null) {
          isListening.value = true;
          // Smooth small jitters
          final diff = (heading - headingNotifier.value).abs();
          if (diff > 0.5) {
            headingNotifier.value = heading;
          }
        }
      });
    } catch (_) {}
  }
}
