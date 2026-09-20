import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/location_update.dart';
import '../../providers/family_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/permissions_provider.dart';
import '../../widgets/common_widgets.dart';

/// Sections 10 & 11. Location only ever comes from an authenticated backend
/// call through [LocationProvider] - there is no public link, and the
/// sharing state is always shown plainly rather than assumed.
class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  void _load() {
    final id = context.read<FamilyProvider>().primaryElderlyUserId;
    if (id != null) context.read<LocationProvider>().load(id);
  }

  String _stateMessage(LocationSharingState state) {
    switch (state) {
      case LocationSharingState.on:
        return 'Location sharing is currently ON.';
      case LocationSharingState.off:
        return 'Location sharing is currently OFF.';
      case LocationSharingState.permissionDenied:
        return "Their device isn't allowing location access right now.";
      case LocationSharingState.deviceOffline:
        return 'Their device appears to be offline.';
      case LocationSharingState.unknown:
        return "We can't tell the current sharing state right now.";
    }
  }

  Future<void> _openInMaps(LocationUpdate location) async {
    if (!location.hasCoordinates) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${location.latitude},${location.longitude}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final permissions = context.watch<PermissionsProvider>();
    final locationState = context.watch<LocationProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Location')),
      body: Builder(builder: (context) {
        if (permissions.isLoading) return const LoadingView();
        if (!permissions.permissions.location) {
          return const PermissionLockedView(category: 'Location');
        }
        if (locationState.isLoading && locationState.location == null) return const LoadingView();
        if (locationState.error != null && locationState.location == null) {
          return ErrorView(message: locationState.error!.message, onRetry: _load);
        }
        final location = locationState.location;
        if (location == null) return const EmptyState(icon: Icons.location_off_rounded, title: 'No location data');

        return RefreshIndicator(
          onRefresh: () async => _load(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          location.sharingState == LocationSharingState.on ? Icons.share_location_rounded : Icons.location_disabled_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_stateMessage(location.sharingState), style: Theme.of(context).textTheme.titleMedium)),
                      ],
                    ),
                    if (location.sharingState == LocationSharingState.on && location.address != null) ...[
                      const SizedBox(height: 16),
                      Text(location.address!, style: Theme.of(context).textTheme.bodyLarge),
                    ],
                    const SizedBox(height: 12),
                    LastUpdatedLabel(time: location.updatedAt),
                    if (location.sharingState == LocationSharingState.on && location.hasCoordinates) ...[
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: () => _openInMaps(location),
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Open in Maps'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
