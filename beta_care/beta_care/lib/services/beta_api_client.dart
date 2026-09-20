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

/// Everything Beta Care needs from the existing Beta backend (section 20).
/// [HttpBetaApiClient] implements this against the real REST API;
/// [MockBetaApiClient] implements it entirely in memory. Screens and
/// providers only ever depend on this interface, never on a concrete
/// implementation, so swapping one for the other is a one-line change in
/// main.dart.
abstract class BetaApiClient {
  Future<CaregiverProfile> getMe();

  Future<List<FamilyLink>> getFamilyLinks();
  Future<FamilyLink> inviteElderly({required String invitationCode, required String relationshipLabel});
  Future<void> removeFamilyLink(String linkId);
  Future<List<CoCaregiver>> getCoCaregivers(String elderlyUserId);

  /// Read-only from Beta Care: the elderly person is the one who grants and
  /// revokes permissions, from their own Beta AI app.
  Future<PermissionSet> getPermissions(String elderlyUserId);

  Future<HealthSnapshot> getHealthLatest(String elderlyUserId);
  Future<List<HealthHistoryPoint>> getHealthHistory(String elderlyUserId);

  Future<List<MedicationDose>> getMedicationsToday(String elderlyUserId);
  Future<List<MedicationDay>> getMedicationHistory(String elderlyUserId, {int days = 7});

  Future<LocationUpdate> getLatestLocation(String elderlyUserId);

  Future<List<DeviceStatus>> getDevices(String elderlyUserId);

  Future<List<AlertItem>> getAlerts(String elderlyUserId);
  Future<void> acknowledgeAlert(String alertId);

  Future<NotificationPreferences> getNotificationSettings();
  Future<void> updateNotificationSettings(NotificationPreferences prefs);

  /// There's no dedicated `/dashboard` endpoint in section 20's list, so
  /// [HttpBetaApiClient] composes this from the calls above. The mock
  /// returns it directly.
  Future<DashboardSnapshot> getDashboardSummary(String elderlyUserId);
}

/// In-memory sample data standing in for "the existing Beta backend" until
/// this is wired to the real thing. Every method has a small artificial
/// delay so loading states in the UI are visible and honest during
/// development, and every value here matches the worked examples in the
/// Beta Care spec.
class MockBetaApiClient implements BetaApiClient {
  static const _elderly = ElderlyUser(
    id: 'mock-elderly-1',
    displayName: 'Dad',
    phoneNumber: '+91 98765 43210',
  );

  static DateTime _todayAt(int hour, int minute) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour, minute);
  }

  final List<AlertItem> _alerts = [
    AlertItem(
      id: 'alert-1',
      type: AlertType.health,
      status: AlertStatus.unacknowledged,
      title: 'Health alert',
      message: 'An unusual reading was detected. Reading outside configured range. Consider contacting a medical professional if this continues.',
      occurredAt: _todayAt(10, 42),
    ),
    AlertItem(
      id: 'alert-2',
      type: AlertType.medication,
      status: AlertStatus.acknowledged,
      title: 'Medication confirmed',
      message: 'Night medication was confirmed at 8:12 PM.',
      occurredAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    AlertItem(
      id: 'alert-3',
      type: AlertType.emergency,
      status: AlertStatus.acknowledged,
      title: 'Emergency alert',
      message: 'Dad may need assistance.',
      occurredAt: DateTime.now().subtract(const Duration(days: 4)),
      locationAvailable: true,
    ),
  ];

  NotificationPreferences _notificationPrefs = const NotificationPreferences();

  Future<void> _delay() => Future.delayed(const Duration(milliseconds: 500));

  @override
  Future<CaregiverProfile> getMe() async {
    await _delay();
    return const CaregiverProfile(id: 'mock-caregiver-1', name: 'Priya Sharma', email: 'priya.sharma@example.com');
  }

  @override
  Future<List<FamilyLink>> getFamilyLinks() async {
    await _delay();
    return [
      FamilyLink(
        id: 'link-1',
        elderlyUser: _elderly,
        status: RelationshipStatus.active,
        relationshipLabel: 'Son',
        createdAt: DateTime.now().subtract(const Duration(days: 96)),
      ),
    ];
  }

  @override
  Future<FamilyLink> inviteElderly({required String invitationCode, required String relationshipLabel}) async {
    await _delay();
    if (invitationCode.trim().length < 4) {
      throw const UnknownApiException('That invitation code doesn\'t look right. Please check it and try again.');
    }
    return FamilyLink(
      id: 'link-${DateTime.now().millisecondsSinceEpoch}',
      elderlyUser: const ElderlyUser(id: 'mock-elderly-2', displayName: 'New Connection'),
      status: RelationshipStatus.pending,
      relationshipLabel: relationshipLabel,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> removeFamilyLink(String linkId) async {
    await _delay();
  }

  @override
  Future<List<CoCaregiver>> getCoCaregivers(String elderlyUserId) async {
    await _delay();
    return const [
      CoCaregiver(id: 'co-1', name: 'Mom', relationshipLabel: 'Spouse', status: RelationshipStatus.active),
      CoCaregiver(id: 'co-2', name: 'Brother', relationshipLabel: 'Son', status: RelationshipStatus.active),
    ];
  }

  @override
  Future<PermissionSet> getPermissions(String elderlyUserId) async {
    await _delay();
    return const PermissionSet(
      health: true,
      medication: true,
      location: true,
      activity: true,
      device: true,
      emergency: true,
      conversations: false,
    );
  }

  @override
  Future<HealthSnapshot> getHealthLatest(String elderlyUserId) async {
    await _delay();
    return HealthSnapshot(
      heartRateBpm: 72,
      steps: 6421,
      sleepDuration: const Duration(hours: 7, minutes: 20),
      bloodOxygenPercent: 97,
      lastSyncedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      activeAlert: HealthAlertInfo(
        description: 'Reading outside configured range',
        detectedAt: _todayAt(10, 42),
        source: 'Connected wearable',
      ),
    );
  }

  @override
  Future<List<HealthHistoryPoint>> getHealthHistory(String elderlyUserId) async {
    await _delay();
    final now = DateTime.now();
    return List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      return HealthHistoryPoint(type: HealthMetricType.steps, value: 4200 + (i * 380 % 2600), recordedAt: day);
    });
  }

  @override
  Future<List<MedicationDose>> getMedicationsToday(String elderlyUserId) async {
    await _delay();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final morning = today.add(const Duration(hours: 8));
    final afternoon = today.add(const Duration(hours: 14));
    final night = today.add(const Duration(hours: 20));
    final nightIsOverdue = now.isAfter(night.add(const Duration(minutes: 30)));

    return [
      MedicationDose(
        id: 'dose-morning',
        medicationName: 'Morning Medicine',
        scheduledAt: morning,
        status: MedicationStatus.taken,
        confirmedAt: morning.add(const Duration(minutes: 7)),
      ),
      MedicationDose(
        id: 'dose-afternoon',
        medicationName: 'Afternoon Medicine',
        scheduledAt: afternoon,
        status: MedicationStatus.taken,
        confirmedAt: afternoon.add(const Duration(minutes: 15)),
      ),
      MedicationDose(
        id: 'dose-night',
        medicationName: 'Night Medicine',
        scheduledAt: night,
        status: nightIsOverdue ? MedicationStatus.missed : MedicationStatus.pending,
      ),
    ];
  }

  @override
  Future<List<MedicationDay>> getMedicationHistory(String elderlyUserId, {int days = 7}) async {
    await _delay();
    final now = DateTime.now();
    return List.generate(days, (i) {
      final date = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final isSlipDay = i == 2; // one day in the history shows a missed dose, for realism
      return MedicationDay(date: date, doses: [
        MedicationDose(
          id: 'hist-$i-morning',
          medicationName: 'Morning',
          scheduledAt: date.add(const Duration(hours: 8)),
          status: MedicationStatus.taken,
          confirmedAt: date.add(const Duration(hours: 8, minutes: 6)),
        ),
        MedicationDose(
          id: 'hist-$i-afternoon',
          medicationName: 'Afternoon',
          scheduledAt: date.add(const Duration(hours: 14)),
          status: MedicationStatus.taken,
          confirmedAt: date.add(const Duration(hours: 14, minutes: 12)),
        ),
        MedicationDose(
          id: 'hist-$i-night',
          medicationName: 'Night',
          scheduledAt: date.add(const Duration(hours: 20)),
          status: isSlipDay ? MedicationStatus.missed : MedicationStatus.taken,
          confirmedAt: isSlipDay ? null : date.add(const Duration(hours: 20, minutes: 9)),
        ),
      ]);
    });
  }

  @override
  Future<LocationUpdate> getLatestLocation(String elderlyUserId) async {
    await _delay();
    return LocationUpdate(
      sharingState: LocationSharingState.on,
      latitude: 28.6280,
      longitude: 77.3649,
      address: 'Sector 62, Noida, Uttar Pradesh',
      updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    );
  }

  @override
  Future<List<DeviceStatus>> getDevices(String elderlyUserId) async {
    await _delay();
    return [
      DeviceStatus(
        id: 'device-1',
        name: 'Health Band',
        connectionState: DeviceConnectionState.connected,
        batteryPercent: 74,
        lastSyncedAt: DateTime.now().subtract(const Duration(minutes: 2)),
        supportedActions: const [],
      ),
    ];
  }

  @override
  Future<List<AlertItem>> getAlerts(String elderlyUserId) async {
    await _delay();
    return List.unmodifiable(_alerts..sort((a, b) => b.occurredAt.compareTo(a.occurredAt)));
  }

  @override
  Future<void> acknowledgeAlert(String alertId) async {
    await _delay();
    final index = _alerts.indexWhere((a) => a.id == alertId);
    if (index == -1) throw const NotFoundException();
    _alerts[index] = _alerts[index].copyWith(status: AlertStatus.acknowledged);
  }

  @override
  Future<NotificationPreferences> getNotificationSettings() async {
    await _delay();
    return _notificationPrefs;
  }

  @override
  Future<void> updateNotificationSettings(NotificationPreferences prefs) async {
    await _delay();
    _notificationPrefs = prefs;
  }

  Future<T?> _tryOrNull<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on UnauthorizedException {
      // Section 4: an ungranted category is an expected, normal state, not
      // a failure - the detail screens are what show the precise "not
      // shared with you" message via PermissionsProvider. The dashboard
      // just quietly leaves that row at its neutral default.
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
    final medicationNeedsAttention = doses.any(
      (d) => d.status == MedicationStatus.missed || d.status == MedicationStatus.skipped,
    );
    final unacknowledged = alerts.where((a) => a.status == AlertStatus.unacknowledged).length;
    final devicesConnected =
        devices.isNotEmpty && devices.every((d) => d.connectionState == DeviceConnectionState.connected);

    final overall = combineStatusLevels([
      health?.statusLevel ?? StatusLevel.unknown,
      doses.isEmpty ? StatusLevel.unknown : (medicationNeedsAttention ? StatusLevel.attention : StatusLevel.normal),
      devices.isEmpty ? StatusLevel.unknown : (devicesConnected ? StatusLevel.normal : StatusLevel.attention),
      unacknowledged > 0 ? StatusLevel.attention : StatusLevel.normal,
    ]);

    return DashboardSnapshot(
      elderlyUser: _elderly,
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
