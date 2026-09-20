import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/time_format.dart';
import '../../models/alert_item.dart';
import '../../providers/alerts_provider.dart';
import '../../providers/family_provider.dart';
import '../../widgets/common_widgets.dart';
import '../location/location_screen.dart';

/// Section 12 & 13. Emergency alerts get their own unmistakable treatment;
/// everything else is a calm, ordinary list row - the goal is to reduce
/// anxiety, not manufacture it (section 28).
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  void _load() {
    final id = context.read<FamilyProvider>().primaryElderlyUserId;
    if (id != null) context.read<AlertsProvider>().load(id);
  }

  IconData _iconFor(AlertType type) {
    switch (type) {
      case AlertType.health:
        return Icons.favorite_rounded;
      case AlertType.medication:
        return Icons.medication_rounded;
      case AlertType.emergency:
        return Icons.emergency_rounded;
      case AlertType.device:
        return Icons.watch_rounded;
      case AlertType.location:
        return Icons.location_on_rounded;
      case AlertType.general:
        return Icons.notifications_rounded;
    }
  }

  Future<void> _call(String phoneNumber) async {
    await launchUrl(Uri(scheme: 'tel', path: phoneNumber));
  }

  @override
  Widget build(BuildContext context) {
    final alerts = context.watch<AlertsProvider>();
    final elderlyUser = context.watch<FamilyProvider>().primaryLink?.elderlyUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: Builder(builder: (context) {
        if (alerts.isLoading && alerts.alerts.isEmpty) return const LoadingView();
        if (alerts.error != null && alerts.alerts.isEmpty) {
          return ErrorView(message: alerts.error!.message, onRetry: _load);
        }
        if (alerts.alerts.isEmpty) {
          return const EmptyState(icon: Icons.notifications_none_rounded, title: 'No new alerts', subtitle: "You're all caught up.");
        }
        return RefreshIndicator(
          onRefresh: () async => _load(),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: alerts.alerts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final alert = alerts.alerts[i];
              if (alert.isEmergency) {
                return _EmergencyCard(
                  alert: alert,
                  elderlyName: elderlyUser?.displayName ?? 'They',
                  phoneNumber: elderlyUser?.phoneNumber,
                  onCall: _call,
                  onViewLocation: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LocationScreen())),
                  onAcknowledge: () => context.read<AlertsProvider>().acknowledge(alert.id),
                );
              }
              return SectionCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_iconFor(alert.type), color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(alert.title, style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(alert.message, style: Theme.of(context).textTheme.bodyMedium),
                          const SizedBox(height: 6),
                          Text(formatRelativeTime(alert.occurredAt), style: Theme.of(context).textTheme.bodyMedium),
                        ],
                      ),
                    ),
                    if (alert.status == AlertStatus.unacknowledged)
                      IconButton(
                        tooltip: 'Mark as read',
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        onPressed: () => context.read<AlertsProvider>().acknowledge(alert.id),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      }),
    );
  }
}

class _EmergencyCard extends StatelessWidget {
  final AlertItem alert;
  final String elderlyName;
  final String? phoneNumber;
  final Future<void> Function(String) onCall;
  final VoidCallback onViewLocation;
  final VoidCallback onAcknowledge;

  const _EmergencyCard({
    required this.alert,
    required this.elderlyName,
    required this.phoneNumber,
    required this.onCall,
    required this.onViewLocation,
    required this.onAcknowledge,
  });

  @override
  Widget build(BuildContext context) {
    final responded = alert.status == AlertStatus.acknowledged;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: responded ? AppColors.coral.withValues(alpha: 0.06) : AppColors.coral.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.coral.withValues(alpha: responded ? 0.2 : 0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emergency_rounded, color: AppColors.coral),
              const SizedBox(width: 8),
              Text(
                responded ? 'EMERGENCY (RESPONDED)' : 'EMERGENCY',
                style: const TextStyle(color: AppColors.coral, fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('$elderlyName may need assistance.', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 6),
          Text('Time: ${formatClockTime(alert.occurredAt)}', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (alert.locationAvailable)
                OutlinedButton.icon(onPressed: onViewLocation, icon: const Icon(Icons.location_on_outlined), label: const Text('View Location')),
              if (phoneNumber != null)
                OutlinedButton.icon(onPressed: () => onCall(phoneNumber!), icon: const Icon(Icons.call_outlined), label: const Text('Call')),
              if (!responded)
                ElevatedButton.icon(
                  onPressed: onAcknowledge,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.coral),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Mark as Responded'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
