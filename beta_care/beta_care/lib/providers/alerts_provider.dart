import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/exceptions.dart';
import '../models/alert_item.dart';
import '../services/beta_api_client.dart';
import '../services/notification_service.dart';

class AlertsProvider extends ChangeNotifier {
  final BetaApiClient _api;
  final NotificationService _notifications;
  String? _elderlyUserId;
  StreamSubscription<PushNotification>? _pushSub;

  AlertsProvider(this._api, this._notifications) {
    // A push notification about an alert is a good reason to quietly
    // refresh the list, so the badge count is right by the time the
    // caregiver opens the Alerts screen (section 13).
    _pushSub = _notifications.onNotification.listen((_) {
      final id = _elderlyUserId;
      if (id != null) load(id);
    });
  }

  bool isLoading = false;
  AppException? error;
  List<AlertItem> alerts = [];

  int get unacknowledgedCount => alerts.where((a) => a.status == AlertStatus.unacknowledged).length;

  Future<void> load(String elderlyUserId) async {
    _elderlyUserId = elderlyUserId;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      alerts = await _api.getAlerts(elderlyUserId);
    } on AppException catch (e) {
      error = e;
    } catch (_) {
      error = const UnknownApiException();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> acknowledge(String alertId) async {
    final index = alerts.indexWhere((a) => a.id == alertId);
    if (index == -1) return;
    final previous = alerts[index];
    alerts[index] = previous.copyWith(status: AlertStatus.acknowledged);
    notifyListeners();
    try {
      await _api.acknowledgeAlert(alertId);
    } on AppException {
      alerts[index] = previous; // roll back on failure
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _pushSub?.cancel();
    super.dispose();
  }
}
