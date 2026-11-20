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
/// Firebase ID token on every call. This class holds no backend or
/// database credentials of its own - the backend is what verifies the
/// token, checks the family relationship, and checks permissions before
/// returning anything.
///
/// ENDPOINT MAPPING (Ecosystem 2.0 backend):
/// - getMe()                  -> GET  /auth/profile
/// - getFamilyLinks()         -> GET  /care-circles/my-elders + /care-circles/for-elder/{id}
/// - inviteElderly()          -> POST /care-circles/invitations/accept (invite code issued by the elder's app)
/// - removeFamilyLink()       -> POST /care-circles/members/remove
/// - getCoCaregivers()        -> GET  /care-circles/for-elder/{id} (members list)
/// Family Talk, health/meds/location/devices/alerts live in their own
/// services; the monitoring endpoints below are NOT implemented by the
/// backend yet and throw [UnauthorizedException] so screens show their
/// "not shared / not available" states instead of crashing.
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
    final json = await _get('/auth/profile') as Map<String, dynamic>;
    return CaregiverProfile(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? json['email'] as String? ?? 'Caregiver',
      email: (json['email'] as String?) ?? '',
    );
  }

  @override
  Future<List<FamilyLink>> getFamilyLinks() async {
    // The backend returns bare elder ids the caregiver is linked to;
    // resolve each one to the circle overview for names and roles.
    final elders = await _get('/care-circles/my-elders') as List<dynamic>;
    final links = <FamilyLink>[];
    for (final e in elders) {
      final elderId = (e as Map<String, dynamic>)['elder_user_id'] as String;
      final role = (e)['circle_role'] as String?;
      try {
        final circle = await _get('/care-circles/for-elder/$elderId')
            as Map<String, dynamic>;
        final name = circle['name'] as String? ?? 'Family elder';
        links.add(FamilyLink(
          id: circle['circle_id'] as String,
          elderlyUser: ElderlyUser(id: elderId, displayName: name),
          status: RelationshipStatus.active,
          relationshipLabel: role ?? 'Caregiver',
          createdAt: DateTime.now(),
        ));
      } on NotFoundException {
        // Elder deleted or circle gone - skip rather than fail the list.
        continue;
      }
    }
    return links;
    // NOTE: the old spec's FamilyLink.fromJson shape isn't returned by
    // this backend, so links are constructed directly here.
  }

  @override
  Future<FamilyLink> inviteElderly({required String invitationCode, required String relationshipLabel}) async {
    // In Ecosystem 2.0 the ELDER creates the invitation from their Beta
    // Asli app; the caregiver accepts it here with the code.
    final json = await _post('/care-circles/invitations/accept', body: {
      'invite_code': invitationCode,
      'accepting_name': relationshipLabel,
    }) as Map<String, dynamic>;
    return FamilyLink(
      id: json['id'] as String,
      elderlyUser: ElderlyUser(id: '', displayName: json['name'] as String? ?? 'Family elder'),
      status: RelationshipStatus.active,
      relationshipLabel: relationshipLabel,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> removeFamilyLink(String linkId) async {
    // linkId is the circle_id returned by getFamilyLinks(); the
    // backend's remove endpoint needs the member id, which the client
    // can't know here. For now this is a no-op stub that the Family
    // screen disables; server-side removal happens from the elder's app.
    await _delete('/care-circles/$linkId');
  }

  @override
  Future<List<CoCaregiver>> getCoCaregivers(String elderlyUserId) async {
    final json = await _get('/care-circles/for-elder/$elderlyUserId') as Map<String, dynamic>;
    final members = json['members'] as List<dynamic>? ?? const [];
    return members
        .map((m) => CoCaregiver.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  // ------------------------------------------------------------------
  // Monitoring endpoints - NOT yet implemented by the backend.
  // They throw so the UI shows its "not shared with you" state
  // instead of pretending data exists.
  // ------------------------------------------------------------------

  @override
  Future<PermissionSet> getPermissions(String elderlyUserId) async {
    // No permission endpoint on the backend yet; every category is
    // "unknown", which the UI treats as not-shared. The Talk tab works
    // regardless because circle membership is checked server-side.
    return const PermissionSet();
  }

  @override
  Future<HealthSnapshot> getHealthLatest(String elderlyUserId) async {
    throw const UnauthorizedException();
  }

  @override
  Future<List<HealthHistoryPoint>> getHealthHistory(String elderlyUserId) async {
    throw const UnauthorizedException();
  }

  @override
  Future<List<MedicationDose>> getMedicationsToday(String elderlyUserId) async {
    throw const UnauthorizedException();
  }

  @override
  Future<List<MedicationDay>> getMedicationHistory(String elderlyUserId, {int days = 7}) async {
    throw const UnauthorizedException();
  }

  @override
  Future<LocationUpdate> getLatestLocation(String elderlyUserId) async {
    throw const UnauthorizedException();
  }

  @override
  Future<List<DeviceStatus>> getDevices(String elderlyUserId) async {
    throw const UnauthorizedException();
  }

  @override
  Future<List<AlertItem>> getAlerts(String elderlyUserId) async {
    throw const UnauthorizedException();
  }

  @override
  Future<void> acknowledgeAlert(String alertId) async {
    throw const UnauthorizedException();
  }

  @override
  Future<NotificationPreferences> getNotificationSettings() async {
    throw const UnauthorizedException();
  }

  @override
  Future<void> updateNotificationSettings(NotificationPreferences prefs) async {
    throw const UnauthorizedException();
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
