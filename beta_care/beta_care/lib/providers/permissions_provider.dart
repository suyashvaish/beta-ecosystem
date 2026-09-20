import 'package:flutter/foundation.dart';

import '../core/exceptions.dart';
import '../models/permission_set.dart';
import '../services/beta_api_client.dart';

/// Read-only view of the caregiver's own access grants for one elderly
/// user. Every monitoring screen checks this BEFORE calling its own data
/// endpoint, so an unpermitted category shows a calm "not shared with you"
/// state immediately instead of an error round-trip (section 4 UX, backed
/// by real backend enforcement per section 21).
class PermissionsProvider extends ChangeNotifier {
  final BetaApiClient _api;
  PermissionsProvider(this._api);

  bool isLoading = false;
  AppException? error;
  PermissionSet permissions = PermissionSet.none;
  String? _loadedForElderlyUserId;

  Future<void> load(String elderlyUserId) async {
    if (_loadedForElderlyUserId == elderlyUserId && !isLoading && error == null) return;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      permissions = await _api.getPermissions(elderlyUserId);
      _loadedForElderlyUserId = elderlyUserId;
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
