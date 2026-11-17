import 'dart:html' as html;
import 'package:flutter/foundation.dart';

enum NetQuality { fast, weak, offline }

class OfflineHelper {
  static final ValueNotifier<bool> isOnline = ValueNotifier<bool>(
    html.window.navigator.onLine ?? true,
  );

  static final ValueNotifier<NetQuality> netQuality = ValueNotifier<NetQuality>(
    (html.window.navigator.onLine ?? true) ? NetQuality.fast : NetQuality.offline,
  );

  static final ValueNotifier<bool> turboDataSaver = ValueNotifier<bool>(false);

  static void init() {
    _updateStatus();

    html.window.addEventListener('online', (_) => _updateStatus());
    html.window.addEventListener('offline', (_) => _updateStatus());

    try {
      final conn = (html.window.navigator as dynamic).connection;
      if (conn != null) {
        conn.addEventListener('change', (_) => _updateStatus());
      }
    } catch (_) {}
  }

  static void _updateStatus() {
    final online = html.window.navigator.onLine ?? true;
    isOnline.value = online;

    if (!online) {
      netQuality.value = NetQuality.offline;
      return;
    }

    try {
      final conn = (html.window.navigator as dynamic).connection;
      if (conn != null) {
        final effectiveType = conn.effectiveType?.toString().toLowerCase() ?? '';
        final rtt = conn.rtt as num? ?? 100;
        if (effectiveType == '2g' || effectiveType == 'slow-2g' || effectiveType == '3g' || rtt > 600) {
          netQuality.value = NetQuality.weak;
          return;
        }
      }
    } catch (_) {}

    netQuality.value = NetQuality.fast;
  }
}
