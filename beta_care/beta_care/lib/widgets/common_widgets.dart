import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/time_format.dart';

class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: padding, child: child));
}

class LastUpdatedLabel extends StatelessWidget {
  final DateTime? time;
  const LastUpdatedLabel({super.key, this.time});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule_rounded, size: 14, color: style?.color),
        const SizedBox(width: 4),
        Text('Last updated ${formatRelativeTime(time)}', style: style),
      ],
    );
  }
}

/// Section 25: shown at the top of a screen (not instead of it) whenever
/// [ConnectivityProvider.isOnline] is false, so old data is never mistaken
/// for current data.
class OfflineBanner extends StatelessWidget {
  final DateTime? lastUpdated;
  const OfflineBanner({super.key, this.lastUpdated});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.slate.withValues(alpha: 0.15),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.slate),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              lastUpdated != null
                  ? "You're offline. Showing the last synchronized information, from ${formatRelativeTime(lastUpdated)}."
                  : "You're offline.",
              style: const TextStyle(fontSize: 13, color: AppColors.slate, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section 26: plain language, never a status code, always a next step.
class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 40, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

/// Sections 4 & 18: what a screen shows instead of data when the elderly
/// person hasn't shared this category - a plain statement, not an error.
class PermissionLockedView extends StatelessWidget {
  final String category;
  const PermissionLockedView({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final bodyColor = Theme.of(context).textTheme.bodyMedium?.color;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 40, color: bodyColor),
            const SizedBox(height: 12),
            Text(
              "$category hasn't been shared with you",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'They can turn this on from their Privacy settings if you need it.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final bodyColor = Theme.of(context).textTheme.bodyMedium?.color;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: bodyColor),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
