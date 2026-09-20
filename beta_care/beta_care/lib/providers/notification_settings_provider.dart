import 'package:flutter/foundation.dart';

import '../core/exceptions.dart';
import '../models/notification_preferences.dart';
import '../services/beta_api_client.dart';

class NotificationSettingsProvider extends ChangeNotifier {
  final BetaApiClient _api;
  NotificationSettingsProvider(this._api);

  bool isLoading = false;
  AppException? error;
  NotificationPreferences preferences = const NotificationPreferences();

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      preferences = await _api.getNotificationSettings();
    } on AppException catch (e) {
      error = e;
    } catch (_) {
      error = const UnknownApiException();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> update(NotificationPreferences updated) async {
    final previous = preferences;
    preferences = updated; // optimistic, so the switch feels instant
    notifyListeners();
    try {
      await _api.updateNotificationSettings(updated);
    } on AppException {
      preferences = previous;
      notifyListeners();
    }
  }
}
