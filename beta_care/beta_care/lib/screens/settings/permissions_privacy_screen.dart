import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../providers/family_provider.dart';
import '../../providers/permissions_provider.dart';
import '../../widgets/common_widgets.dart';

/// Section 18. Read-only by design - the elderly person grants and revokes
/// these from their own Beta AI app, never from here.
class PermissionsPrivacyScreen extends StatefulWidget {
  const PermissionsPrivacyScreen({super.key});

  @override
  State<PermissionsPrivacyScreen> createState() => _PermissionsPrivacyScreenState();
}

class _PermissionsPrivacyScreenState extends State<PermissionsPrivacyScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final id = context.read<FamilyProvider>().primaryElderlyUserId;
      if (id != null) context.read<PermissionsProvider>().load(id);
    });
  }

  Widget _row(BuildContext context, {required String label, required bool granted}) {
    final color = granted ? AppColors.sage : AppColors.slate;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(granted ? Icons.check_circle_rounded : Icons.cancel_rounded, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final permissions = context.watch<PermissionsProvider>();
    final elderlyName = context.watch<FamilyProvider>().primaryLink?.elderlyUser.displayName ?? 'them';

    return Scaffold(
      appBar: AppBar(title: const Text('Your Access')),
      body: Builder(builder: (context) {
        if (permissions.isLoading) return const LoadingView();
        if (permissions.error != null) return ErrorView(message: permissions.error!.message);

        final p = permissions.permissions;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'This is what $elderlyName has shared with you. They can change this any time from their own app.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text('YOU CAN CURRENTLY VIEW', style: Theme.of(context).textTheme.labelMedium),
            SectionCard(
              child: Column(
                children: [
                  if (p.health) _row(context, label: 'Health', granted: true),
                  if (p.medication) _row(context, label: 'Medication', granted: true),
                  if (p.location) _row(context, label: 'Location', granted: true),
                  if (p.activity) _row(context, label: 'Activity', granted: true),
                  if (p.device) _row(context, label: 'Device status', granted: true),
                  if (p.emergency) _row(context, label: 'Emergency alerts', granted: true),
                  if (!(p.health || p.medication || p.location || p.activity || p.device || p.emergency))
                    Text('Nothing yet.', style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('YOU CANNOT VIEW', style: Theme.of(context).textTheme.labelMedium),
            SectionCard(
              child: Column(
                children: [
                  _row(context, label: 'Private conversations', granted: false),
                  _row(context, label: 'Personal memories', granted: false),
                  if (!p.health) _row(context, label: 'Health', granted: false),
                  if (!p.medication) _row(context, label: 'Medication', granted: false),
                  if (!p.location) _row(context, label: 'Location', granted: false),
                  if (!p.activity) _row(context, label: 'Activity', granted: false),
                  if (!p.device) _row(context, label: 'Device status', granted: false),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}
