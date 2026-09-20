import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/exceptions.dart';
import '../models/dashboard_snapshot.dart';
import '../models/status_level.dart';
import '../models/user_models.dart';
import '../services/beta_api_client.dart';

const _cachePrefix = 'cache.dashboard';

/// Powers the home screen (section 5). On a [NetworkException] this falls
/// back to the last snapshot it successfully cached to disk, and flags
/// [isShowingCachedData] so the UI can show an honest "you're offline,
/// showing last synchronized information" banner instead of silently
/// presenting stale data as current (section 25).
class DashboardProvider extends ChangeNotifier {
  final BetaApiClient _api;
  DashboardProvider(this._api);

  bool isLoading = false;
  AppException? error;
  DashboardSnapshot? snapshot;
  bool isShowingCachedData = false;

  Future<void> load(String elderlyUserId) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final result = await _api.getDashboardSummary(elderlyUserId);
      snapshot = result;
      isShowingCachedData = false;
      // Fire-and-forget: caching failures shouldn't block the UI update.
      _cache(result);
    } on NetworkException catch (e) {
      final cached = await _readCache();
      if (cached != null) {
        snapshot = cached;
        isShowingCachedData = true;
      } else {
        error = e;
      }
    } on AppException catch (e) {
      error = e;
    } catch (_) {
      error = const UnknownApiException();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _cache(DashboardSnapshot s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_cachePrefix.elderlyUser', jsonEncode(s.elderlyUser.toJson()));
    await prefs.setString('$_cachePrefix.overallStatus', s.overallStatus.name);
    await prefs.setString('$_cachePrefix.medicationSummary', s.medicationSummary);
    await prefs.setBool('$_cachePrefix.medicationNeedsAttention', s.medicationNeedsAttention);
    await prefs.setString('$_cachePrefix.healthHeadline', s.healthHeadline ?? '');
    await prefs.setString('$_cachePrefix.healthStatus', s.healthStatus.name);
    await prefs.setBool('$_cachePrefix.locationSharingOn', s.locationSharingOn);
    await prefs.setString('$_cachePrefix.locationUpdatedAt', s.locationUpdatedAt?.toIso8601String() ?? '');
    await prefs.setBool('$_cachePrefix.deviceConnected', s.deviceConnected);
    await prefs.setInt('$_cachePrefix.unacknowledgedAlertCount', s.unacknowledgedAlertCount);
    await prefs.setString('$_cachePrefix.lastRefreshedAt', s.lastRefreshedAt.toIso8601String());
  }

  Future<DashboardSnapshot?> _readCache() async {
    final prefs = await SharedPreferences.getInstance();
    final elderlyRaw = prefs.getString('$_cachePrefix.elderlyUser');
    if (elderlyRaw == null) return null;
    final locationUpdatedAtRaw = prefs.getString('$_cachePrefix.locationUpdatedAt');
    return DashboardSnapshot(
      elderlyUser: ElderlyUser.fromJson(jsonDecode(elderlyRaw) as Map<String, dynamic>),
      overallStatus: StatusLevel.values.firstWhere(
        (v) => v.name == prefs.getString('$_cachePrefix.overallStatus'),
        orElse: () => StatusLevel.unknown,
      ),
      medicationSummary: prefs.getString('$_cachePrefix.medicationSummary') ?? '',
      medicationNeedsAttention: prefs.getBool('$_cachePrefix.medicationNeedsAttention') ?? false,
      healthHeadline: prefs.getString('$_cachePrefix.healthHeadline'),
      healthStatus: StatusLevel.values.firstWhere(
        (v) => v.name == prefs.getString('$_cachePrefix.healthStatus'),
        orElse: () => StatusLevel.unknown,
      ),
      locationSharingOn: prefs.getBool('$_cachePrefix.locationSharingOn') ?? false,
      locationUpdatedAt: (locationUpdatedAtRaw != null && locationUpdatedAtRaw.isNotEmpty)
          ? DateTime.tryParse(locationUpdatedAtRaw)
          : null,
      deviceConnected: prefs.getBool('$_cachePrefix.deviceConnected') ?? false,
      unacknowledgedAlertCount: prefs.getInt('$_cachePrefix.unacknowledgedAlertCount') ?? 0,
      lastRefreshedAt: DateTime.tryParse(prefs.getString('$_cachePrefix.lastRefreshedAt') ?? '') ?? DateTime.now(),
    );
  }
}
