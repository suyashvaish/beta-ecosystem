import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/time_format.dart';
import '../../models/medication_models.dart';
import '../../providers/family_provider.dart';
import '../../providers/medication_provider.dart';
import '../../providers/permissions_provider.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/status_indicator.dart';

/// Section 8. "Taken" is never shown unless the data actually says so -
/// there is no optimistic assumption here, only what [MedicationProvider]
/// got back from the backend.
class MedicationsScreen extends StatefulWidget {
  const MedicationsScreen({super.key});

  @override
  State<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends State<MedicationsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  void _load() {
    final id = context.read<FamilyProvider>().primaryElderlyUserId;
    if (id != null) context.read<MedicationProvider>().load(id);
  }

  @override
  Widget build(BuildContext context) {
    final permissions = context.watch<PermissionsProvider>();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Medications'),
          bottom: const TabBar(tabs: [Tab(text: 'Today'), Tab(text: 'History')]),
        ),
        body: Builder(builder: (context) {
          if (permissions.isLoading) return const LoadingView();
          if (!permissions.permissions.medication) {
            return const PermissionLockedView(category: 'Medication information');
          }
          return TabBarView(children: [
            _TodayTab(onRetry: _load),
            _HistoryTab(onRetry: _load),
          ]);
        }),
      ),
    );
  }
}

class _TodayTab extends StatelessWidget {
  final VoidCallback onRetry;
  const _TodayTab({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final medication = context.watch<MedicationProvider>();
    if (medication.isLoading && medication.today.isEmpty) return const LoadingView();
    if (medication.error != null && medication.today.isEmpty) {
      return ErrorView(message: medication.error!.message, onRetry: onRetry);
    }
    if (medication.today.isEmpty) {
      return const EmptyState(icon: Icons.medication_outlined, title: 'No medications scheduled today');
    }
    return RefreshIndicator(
      onRefresh: () async => onRetry(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: medication.today.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final dose = medication.today[i];
          return SectionCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dose.medicationName, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text('Scheduled for ${formatClockTime(dose.scheduledAt)}', style: Theme.of(context).textTheme.bodyMedium),
                      if (dose.status == MedicationStatus.taken && dose.confirmedAt != null) ...[
                        const SizedBox(height: 2),
                        Text('Taken at ${formatClockTime(dose.confirmedAt!)}', style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ],
                  ),
                ),
                StatusIndicator(level: dose.status.statusLevel, label: dose.status.label),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  final VoidCallback onRetry;
  const _HistoryTab({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final medication = context.watch<MedicationProvider>();
    if (medication.isLoading && medication.history.isEmpty) return const LoadingView();
    if (medication.error != null && medication.history.isEmpty) {
      return ErrorView(message: medication.error!.message, onRetry: onRetry);
    }
    if (medication.history.isEmpty) {
      return const EmptyState(icon: Icons.history_rounded, title: 'No history yet');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: medication.history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final day = medication.history[i];
        return SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${day.date.day}/${day.date.month}/${day.date.year}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              for (final dose in day.doses)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(dose.medicationName),
                      StatusIndicator(level: dose.status.statusLevel, compact: true),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
