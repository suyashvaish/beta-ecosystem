import 'package:flutter/foundation.dart';

import '../core/exceptions.dart';
import '../models/device_status.dart';
import '../services/beta_api_client.dart';

class DeviceProvider extends ChangeNotifier {
  final BetaApiClient _api;
  DeviceProvider(this._api);

  bool isLoading = false;
  AppException? error;
  List<DeviceStatus> devices = [];

  Future<void> load(String elderlyUserId) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      devices = await _api.getDevices(elderlyUserId);
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
