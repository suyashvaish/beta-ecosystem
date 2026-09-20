import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/time_format.dart';
import '../../models/status_level.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/family_provider.dart';
import '../../providers/permissions_provider.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/status_indicator.dart';
import '../alerts/alerts_screen.dart';
import '../devices/devices_screen.dart';
import '../health/health_screen.dart';
import '../location/location_screen.dart';
import '../medications/medications_screen.dart';

/// Section 5. The whole point of this screen: a caregiver opens the app and
/// understands the elderly person's status within a few seconds, without
/// needing a medical degree to read it.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  void _load() {
    final id = context.read<FamilyProvider>().primaryElderlyUserId;
    if (id != null) context.read<DashboardProvider>().load(id);
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardProvider>();
    final permissions = context.watch<PermissionsProvider>();
    final online = context.watch<ConnectivityProvider>().isOnline;
    final snapshot = dashboard.snapshot;

    return Scaffold(
      appBar: AppBar(title: const Text('Beta Care')),
      body: RefreshIndicator(
        onRefresh: () async => _load(),
        child: Builder(builder: (context) {
          if (dashboard.isLoading && snapshot == null) {
            return const LoadingView();
          }
          if (dashboard.error != null && snapshot == null) {
            return ListView(children: [
              const SizedBox(height: 80),
              ErrorView(message: dashboard.error!.message, onRetry: _load),
            ]);
          }
          if (snapshot == null) {
            return const EmptyState(icon: Icons.dashboard_outlined, title: 'Nothing to show yet');
          }

          final perms = permissions.permissions;
          final showOffline = !online || dashboard.isShowingCachedData;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              if (showOffline) ...[
                const SizedBox(height: 12),
                ClipRRect(borderRadius: BorderRadius.circular(12), child: OfflineBanner(lastUpdated: snapshot.lastRefreshedAt)),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  StatusRingAvatar(
                    initials: snapshot.elderlyUser.displayName.isNotEmpty
                        ? snapshot.elderlyUser.displayName.substring(0, 1).toUpperCase()
                        : '?',
                    photoUrl: snapshot.elderlyUser.photoUrl,
                    level: snapshot.overallStatus,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(snapshot.elderlyUser.displayName, style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 6),
                        StatusIndicator(level: snapshot.overallStatus),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (snapshot.unacknowledgedAlertCount > 0)
                _AlertBanner(
                  count: snapshot.unacknowledgedAlertCount,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AlertsScreen())),
                ),
              if (snapshot.unacknowledgedAlertCount > 0) const SizedBox(height: 12),
              if (perms.medication)
                _DashboardRow(
                  icon: Icons.medication_rounded,
                  title: 'Medication',
                  subtitle: snapshot.medicationSummary,
                  level: snapshot.medicationNeedsAttention ? StatusLevel.attention : StatusLevel.normal,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MedicationsScreen())),
                ),
              if (perms.health)
                _DashboardRow(
                  icon: Icons.favorite_rounded,
                  title: 'Health',
                  subtitle: snapshot.healthHeadline ?? 'Not yet synchronized',
                  level: snapshot.healthStatus,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HealthScreen())),
                ),
              if (perms.location)
                _DashboardRow(
                  icon: Icons.location_on_rounded,
                  title: 'Location',
                  subtitle: snapshot.locationSharingOn
                      ? 'Last updated ${formatRelativeTime(snapshot.locationUpdatedAt)}'
                      : 'Location sharing is off',
                  level: snapshot.locationSharingOn ? StatusLevel.normal : StatusLevel.unknown,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LocationScreen())),
                ),
              if (perms.device)
                _DashboardRow(
                  icon: Icons.watch_rounded,
                  title: 'Device',
                  subtitle: snapshot.deviceConnected ? 'Connected' : 'Disconnected',
                  level: snapshot.deviceConnected ? StatusLevel.normal : StatusLevel.attention,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DevicesScreen())),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _AlertBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.amber.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.notifications_active_rounded, color: AppColors.amber),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                count == 1 ? '1 new alert needs your attention' : '$count new alerts need your attention',
                style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.amber),
          ],
        ),
      ),
    );
  }
}

class _DashboardRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final StatusLevel level;
  final VoidCallback onTap;

  const _DashboardRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.level,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SectionCard(
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              StatusIndicator(level: level, compact: true),
            ],
          ),
        ),
      ),
    );
  }
}
