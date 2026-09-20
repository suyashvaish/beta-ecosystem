import 'package:flutter/foundation.dart';

import '../core/exceptions.dart';
import '../models/health_models.dart';
import '../services/beta_api_client.dart';

class HealthProvider extends ChangeNotifier {
  final BetaApiClient _api;
  HealthProvider(this._api);

  bool isLoading = false;
  AppException? error;
  HealthSnapshot? snapshot;
  List<HealthHistoryPoint> history = [];

  Future<void> load(String elderlyUserId) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _api.getHealthLatest(elderlyUserId),
        _api.getHealthHistory(elderlyUserId),
      ]);
      snapshot = results[0] as HealthSnapshot;
      history = results[1] as List<HealthHistoryPoint>;
    } on AppException catch (e) {
      error = e;
    } catch (_) {
      error = const UnknownApiException();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
