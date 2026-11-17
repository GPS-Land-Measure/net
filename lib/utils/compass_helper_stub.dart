import 'package:flutter/foundation.dart';

class CompassHelper {
  static final ValueNotifier<double> headingNotifier = ValueNotifier<double>(0.0);
  static final ValueNotifier<bool> isListening = ValueNotifier<bool>(false);

  static void init() {}
  static void requestPermissionAndStart() {}
  static void startListening() {}
}
