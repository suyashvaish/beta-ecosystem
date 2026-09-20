import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Tracks whether the device currently has a network path at all. This is
/// intentionally separate from any single screen's own error state - it's
/// what drives the app-wide "You're offline" banner in [AppShell], while a
/// screen's own [AppException] still covers "online, but that specific
/// call failed".
class ConnectivityProvider extends ChangeNotifier {
  bool isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  ConnectivityProvider() {
    Connectivity().checkConnectivity().then(_update);
    _sub = Connectivity().onConnectivityChanged.listen(_update);
  }

  void _update(List<ConnectivityResult> results) {
    final nowOnline = results.any((r) => r != ConnectivityResult.none);
    if (nowOnline != isOnline) {
      isOnline = nowOnline;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
