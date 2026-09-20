import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../core/exceptions.dart';
import '../models/alert_item.dart';
import '../models/dashboard_snapshot.dart';
import '../models/device_status.dart';
import '../models/family_link.dart';
import '../models/health_models.dart';
import '../models/location_update.dart';
import '../models/medication_models.dart';
import '../models/notification_preferences.dart';
import '../models/permission_set.dart';
import '../models/status_level.dart';
import '../models/user_models.dart';
import 'auth_service.dart';
import 'beta_api_client.dart';

/// Talks to the real Beta backend over HTTPS, attaching the caregiver's
/// Firebase ID token on every call (section 19). This class holds no
/// backend or database credentials of its own - the backend is what
/// verifies the token, checks the family relationship, and checks
/// permissions before returning anything (section 21).
///
/// NOTE ON ENDPOINT SHAPES: section 20 lists endpoint paths but doesn't
/// specify how a caregiver with more than one elderly connection is
/// disambiguated. This implementation passes `elderlyUserId` as a query
/// parameter on the per-elderly-user endpoints; adjust `_get`/`_post` calls
/// below if the real backend expects it in the path instead
/// (e.g. `/health/$elderlyUserId`).
class HttpBetaApiClient implements BetaApiClient {
  final AuthService authService;
  final http.Client _client;
  final String baseUrl;

  HttpBetaApiClient({required this.authService, http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? AppConfig.backendBaseUrl;

  Future<Map<String, String>> _headers() async {
    final token = await authService.getIdToken();
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    try {
      final response = await request().timeout(AppConfig.apiTimeout);
      return _decode(response);
    } on TimeoutException {
      throw const NetworkException();
    } on SocketException {
      throw const NetworkException();
    } on http.ClientException {
      throw const NetworkException();
    }
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }
    switch (response.statusCode) {
      case 401:
        throw const NotSignedInException();
      case 403:
        throw const UnauthorizedException();
      case 404:
        throw const NotFoundException();
      default:
        throw const UnknownApiException();
    }
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<dynamic> _get(String path, {Map<String, String>? query}) =>
      _send(() async => _client.get(_uri(path, query), headers: await _headers()));

  Future<dynamic> _post(String path, {Object? body}) =>
      _send(() async => _client.post(_uri(path), headers: await _headers(), body: jsonEncode(body)));

  Future<dynamic> _put(String path, {Object? body}) =>
      _send(() async => _client.put(_uri(path), headers: await _headers(), body: jsonEncode(body)));

  Future<dynamic> _delete(String path) =>
      _send(() async => _client.delete(_uri(path), headers: await _headers()));

  @override
  Future<CaregiverProfile> getMe() async {
    final json = await _get('/users/me') as Map<String, dynamic>;
    return CaregiverProfile.fromJson(json);
  }

  @override
  Future<List<FamilyLink>> getFamilyLinks() async {
    final json = await _get('/family') as List<dynamic>;
    return json.map((e) => FamilyLink.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<FamilyLink> inviteElderly({required String invitationCode, required String relationshipLabel}) async {
    final json = await _post('/family/invite', body: {
      'invitationCode': invitationCode,
      'relationshipLabel': relationshipLabel,
    }) as Map<String, dynamic>;
    return FamilyLink.fromJson(json);
  }

  @override
  Future<void> removeFamilyLink(String linkId) async {
    await _delete('/family/$linkId');
  }

  @override
  Future<List<CoCaregiver>> getCoCaregivers(String elderlyUserId) async {
    // Not explicitly listed in section 20 - assumed to hang off /family.
    // Adjust the path if the real backend exposes this differently.
    final json = await _get('/family/$elderlyUserId/caregivers') as List<dynamic>;
    return json.map((e) => CoCaregiver.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<PermissionSet> getPermissions(String elderlyUserId) async {
    final json = await _get('/permissions', query: {'elderlyUserId': elderlyUserId}) as Map<String, dynamic>;
    return PermissionSet.fromJson(json);
  }

  @override
  Future<HealthSnapshot> getHealthLatest(String elderlyUserId) async {
    final json = await _get('/health', query: {'elderlyUserId': elderlyUserId}) as Map<String, dynamic>;
    return HealthSnapshot.fromJson(json);
  }

  @override
  Future<List<HealthHistoryPoint>> getHealthHistory(String elderlyUserId) async {
    final json = await _get('/health/measurements', query: {'elderlyUserId': elderlyUserId}) as List<dynamic>;
    return json.map((e) => HealthHistoryPoint.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<MedicationDose>> getMedicationsToday(String elderlyUserId) async {
    final json = await _get('/medications', query: {'elderlyUserId': elderlyUserId}) as List<dynamic>;
    return json.map((e) => MedicationDose.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<MedicationDay>> getMedicationHistory(String elderlyUserId, {int days = 7}) async {
    final json = await _get('/medications/history', query: {
      'elderlyUserId': elderlyUserId,
      'days': '$days',
    }) as List<dynamic>;
    return json.map((e) => MedicationDay.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<LocationUpdate> getLatestLocation(String elderlyUserId) async {
    final json = await _get('/location/latest', query: {'elderlyUserId': elderlyUserId}) as Map<String, dynamic>;
    return LocationUpdate.fromJson(json);
  }

  @override
  Future<List<DeviceStatus>> getDevices(String elderlyUserId) async {
    final json = await _get('/devices', query: {'elderlyUserId': elderlyUserId}) as List<dynamic>;
    return json.map((e) => DeviceStatus.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<AlertItem>> getAlerts(String elderlyUserId) async {
    final json = await _get('/alerts', query: {'elderlyUserId': elderlyUserId}) as List<dynamic>;
    return json.map((e) => AlertItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<void> acknowledgeAlert(String alertId) async {
    await _post('/alerts/$alertId/acknowledge');
  }

  @override
  Future<NotificationPreferences> getNotificationSettings() async {
    final json = await _get('/notifications') as Map<String, dynamic>;
    return NotificationPreferences.fromJson(json);
  }

  @override
  Future<void> updateNotificationSettings(NotificationPreferences prefs) async {
    await _put('/notification-settings', body: prefs.toJson());
  }

  Future<T?> _tryOrNull<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on UnauthorizedException {
      return null;
    }
  }

  @override
  Future<DashboardSnapshot> getDashboardSummary(String elderlyUserId) async {
    final health = await _tryOrNull(() => getHealthLatest(elderlyUserId));
    final doses = await _tryOrNull(() => getMedicationsToday(elderlyUserId)) ?? const <MedicationDose>[];
    final location = await _tryOrNull(() => getLatestLocation(elderlyUserId));
    final devices = await _tryOrNull(() => getDevices(elderlyUserId)) ?? const <DeviceStatus>[];
    final alerts = await _tryOrNull(() => getAlerts(elderlyUserId)) ?? const <AlertItem>[];

    final takenCount = doses.where((d) => d.status == MedicationStatus.taken).length;
    final medicationNeedsAttention =
        doses.any((d) => d.status == MedicationStatus.missed || d.status == MedicationStatus.skipped);
    final unacknowledged = alerts.where((a) => a.status == AlertStatus.unacknowledged).length;
    final devicesConnected =
        devices.isNotEmpty && devices.every((d) => d.connectionState == DeviceConnectionState.connected);

    final overall = combineStatusLevels([
      health?.statusLevel ?? StatusLevel.unknown,
      doses.isEmpty ? StatusLevel.unknown : (medicationNeedsAttention ? StatusLevel.attention : StatusLevel.normal),
      devices.isEmpty ? StatusLevel.unknown : (devicesConnected ? StatusLevel.normal : StatusLevel.attention),
      unacknowledged > 0 ? StatusLevel.attention : StatusLevel.normal,
    ]);

    final links = await getFamilyLinks();
    final elderlyUser = links.firstWhere((l) => l.elderlyUser.id == elderlyUserId).elderlyUser;

    return DashboardSnapshot(
      elderlyUser: elderlyUser,
      overallStatus: overall,
      medicationSummary: doses.isEmpty ? 'No medication data shared' : '$takenCount of ${doses.length} confirmed today',
      medicationNeedsAttention: medicationNeedsAttention,
      healthHeadline: health == null ? null : (health.activeAlert?.description ?? 'Normal'),
      healthStatus: health?.statusLevel ?? StatusLevel.unknown,
      locationSharingOn: location?.sharingState == LocationSharingState.on,
      locationUpdatedAt: location?.updatedAt,
      deviceConnected: devicesConnected,
      unacknowledgedAlertCount: unacknowledged,
      lastRefreshedAt: DateTime.now(),
    );
  }
}
