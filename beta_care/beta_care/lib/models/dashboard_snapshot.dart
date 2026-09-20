import 'status_level.dart';
import 'user_models.dart';

/// Everything the home screen (section 5) needs, in one shape. There is no
/// dedicated /dashboard endpoint in the backend contract (section 20), so
/// [HttpBetaApiClient] builds this by calling the health/medication/
/// location/device/alerts endpoints in parallel and folding the results
/// down to one status each - the mock client just returns it directly.
class DashboardSnapshot {
  final ElderlyUser elderlyUser;
  final StatusLevel overallStatus;
  final String medicationSummary; // "2 of 3 confirmed today"
  final bool medicationNeedsAttention;
  final String? healthHeadline; // "Normal" or a short alert description
  final StatusLevel healthStatus;
  final bool locationSharingOn;
  final DateTime? locationUpdatedAt;
  final bool deviceConnected;
  final int unacknowledgedAlertCount;
  final DateTime lastRefreshedAt;

  const DashboardSnapshot({
    required this.elderlyUser,
    required this.overallStatus,
    required this.medicationSummary,
    required this.medicationNeedsAttention,
    required this.healthHeadline,
    required this.healthStatus,
    required this.locationSharingOn,
    this.locationUpdatedAt,
    required this.deviceConnected,
    required this.unacknowledgedAlertCount,
    required this.lastRefreshedAt,
  });
}
