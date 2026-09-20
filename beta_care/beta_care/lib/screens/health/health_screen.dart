import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/time_format.dart';
import '../../models/health_models.dart';
import '../../providers/family_provider.dart';
import '../../providers/health_provider.dart';
import '../../providers/permissions_provider.dart';
import '../../widgets/common_widgets.dart';

/// Sections 6 & 7. Only ever shows fields the wearable actually reported,
/// and never phrases an alert as a diagnosis.
class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  void _load() {
    final id = context.read<FamilyProvider>().primaryElderlyUserId;
    if (id != null) context.read<HealthProvider>().load(id);
  }

  Widget _metricTile(BuildContext context, {required String label, required String? value}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value ?? '—', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 28)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final permissions = context.watch<PermissionsProvider>();
    final health = context.watch<HealthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Health')),
      body: Builder(builder: (context) {
        if (permissions.isLoading) return const LoadingView();
        if (!permissions.permissions.health) {
          return const PermissionLockedView(category: 'Health information');
        }
        if (health.isLoading && health.snapshot == null) return const LoadingView();
        if (health.error != null && health.snapshot == null) {
          return ErrorView(message: health.error!.message, onRetry: _load);
        }
        final snapshot = health.snapshot;
        if (snapshot == null || !snapshot.hasAnyReading) {
          return const EmptyState(
            icon: Icons.favorite_border_rounded,
            title: 'No health data yet',
            subtitle: "This wearable hasn't reported any readings.",
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _load(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (snapshot.activeAlert != null) ...[
                _HealthAlertCard(alert: snapshot.activeAlert!),
                const SizedBox(height: 16),
              ],
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _metricTile(context, label: 'Heart Rate', value: snapshot.heartRateBpm != null ? '${snapshot.heartRateBpm} BPM' : null),
                        _metricTile(context, label: 'Activity', value: snapshot.steps != null ? '${snapshot.steps} steps' : null),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _metricTile(context, label: 'Sleep', value: snapshot.sleepDuration != null ? formatDuration(snapshot.sleepDuration!) : null),
                        _metricTile(context, label: 'Blood Oxygen', value: snapshot.bloodOxygenPercent != null ? '${snapshot.bloodOxygenPercent}%' : null),
                      ],
                    ),
                    const Divider(height: 32),
                    LastUpdatedLabel(time: snapshot.lastSyncedAt),
                  ],
                ),
              ),
              if (health.history.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Recent activity', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                SectionCard(
                  child: Column(
                    children: [
                      for (var i = 0; i < health.history.length; i++) ...[
                        if (i > 0) const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_dayLabel(health.history[i].recordedAt)),
                            Text('${health.history[i].value.round()} steps', style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      }),
    );
  }

  String _dayLabel(DateTime date) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[date.weekday - 1];
  }
}

class _HealthAlertCard extends StatelessWidget {
  final HealthAlertInfo alert;
  const _HealthAlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_rounded, color: AppColors.amber),
              SizedBox(width: 8),
              Text('Health Alert', style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 10),
          // Deliberately factual, never diagnostic (section 7): "alert
          // detected" and "please check on the user", never "diagnosed".
          Text('Alert detected. ${alert.description}. Please check on ${alert.source == 'Connected wearable' ? 'them' : 'the reading'}.'),
          const SizedBox(height: 8),
          Text('Detected at ${formatClockTime(alert.detectedAt)} · Source: ${alert.source}', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          const Text('Status: Needs attention. Consider contacting a medical professional.', style: TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
