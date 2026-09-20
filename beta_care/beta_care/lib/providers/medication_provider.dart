import 'package:flutter/foundation.dart';

import '../core/exceptions.dart';
import '../models/medication_models.dart';
import '../services/beta_api_client.dart';

class MedicationProvider extends ChangeNotifier {
  final BetaApiClient _api;
  MedicationProvider(this._api);

  bool isLoading = false;
  AppException? error;
  List<MedicationDose> today = [];
  List<MedicationDay> history = [];

  Future<void> load(String elderlyUserId) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _api.getMedicationsToday(elderlyUserId),
        _api.getMedicationHistory(elderlyUserId),
      ]);
      today = results[0] as List<MedicationDose>;
      history = results[1] as List<MedicationDay>;
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
