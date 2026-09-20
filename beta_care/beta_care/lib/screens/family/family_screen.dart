import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/family_link.dart';
import '../../widgets/common_widgets.dart';
import 'add_elderly_screen.dart';
import '../../providers/family_provider.dart';

/// Section 15. Shows every elderly connection this caregiver has, plus who
/// else is watching over the same person.
class FamilyScreen extends StatelessWidget {
  const FamilyScreen({super.key});

  Color _statusColor(BuildContext context, RelationshipStatus status) {
    switch (status) {
      case RelationshipStatus.active:
        return Theme.of(context).colorScheme.primary;
      case RelationshipStatus.pending:
        return Colors.orange;
      case RelationshipStatus.rejected:
      case RelationshipStatus.revoked:
        return Theme.of(context).colorScheme.error;
    }
  }

  Future<void> _confirmRemove(BuildContext context, FamilyLink link) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this connection?'),
        content: Text("You'll stop seeing ${link.elderlyUser.displayName}'s information. They will not be notified automatically."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<FamilyProvider>().removeLink(link.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final family = context.watch<FamilyProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Family'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_rounded),
            tooltip: 'Add elderly connection',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddElderlyScreen())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: family.load,
        child: family.isLoading && family.links.isEmpty
            ? const LoadingView()
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (family.error != null) ErrorView(message: family.error!.message, onRetry: family.load),
                  if (family.links.isEmpty && family.error == null)
                    const EmptyState(
                      icon: Icons.people_outline_rounded,
                      title: 'No connections yet',
                      subtitle: 'Add an elderly family member to start monitoring their wellbeing.',
                    ),
                  for (final link in family.links) ...[
                    SectionCard(
                      child: Row(
                        children: [
                          CircleAvatar(child: Text(link.elderlyUser.displayName.substring(0, 1).toUpperCase())),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(link.elderlyUser.displayName, style: Theme.of(context).textTheme.titleMedium),
                                Text('You are their ${link.relationshipLabel}', style: Theme.of(context).textTheme.bodyMedium),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _statusColor(context, link.status).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              link.status.label,
                              style: TextStyle(color: _statusColor(context, link.status), fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_vert_rounded),
                            onPressed: () => _confirmRemove(context, link),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (family.coCaregivers.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Other caregivers', style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 8),
                    SectionCard(
                      child: Column(
                        children: [
                          for (var i = 0; i < family.coCaregivers.length; i++) ...[
                            if (i > 0) const Divider(height: 20),
                            Row(
                              children: [
                                CircleAvatar(radius: 16, child: Text(family.coCaregivers[i].name.substring(0, 1).toUpperCase())),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(family.coCaregivers[i].name, style: Theme.of(context).textTheme.bodyLarge),
                                      Text(family.coCaregivers[i].relationshipLabel, style: Theme.of(context).textTheme.bodyMedium),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
