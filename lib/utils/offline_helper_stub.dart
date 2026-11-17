import 'package:flutter/foundation.dart';

enum NetQuality { fast, weak, offline }

class OfflineHelper {
  static final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);
  static final ValueNotifier<NetQuality> netQuality = ValueNotifier<NetQuality>(NetQuality.fast);
  static final ValueNotifier<bool> turboDataSaver = ValueNotifier<bool>(false);

  static void init() {}
}
