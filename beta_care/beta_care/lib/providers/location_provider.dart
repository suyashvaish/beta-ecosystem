import 'package:flutter/foundation.dart';

import '../core/exceptions.dart';
import '../models/location_update.dart';
import '../services/beta_api_client.dart';

class LocationProvider extends ChangeNotifier {
  final BetaApiClient _api;
  LocationProvider(this._api);

  bool isLoading = false;
  AppException? error;
  LocationUpdate? location;

  Future<void> load(String elderlyUserId) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      location = await _api.getLatestLocation(elderlyUserId);
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
