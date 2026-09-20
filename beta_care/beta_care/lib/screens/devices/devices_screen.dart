import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/device_status.dart';
import '../../providers/device_provider.dart';
import '../../providers/family_provider.dart';
import '../../providers/permissions_provider.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/status_indicator.dart';
import '../../models/status_level.dart';

/// Section 14. Never assumes a caregiver can remotely control a wearable -
/// only ever displays what the backend reports as connected/supported.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  void _load() {
    final id = context.read<FamilyProvider>().primaryElderlyUserId;
    if (id != null) context.read<DeviceProvider>().load(id);
  }

  IconData _batteryIcon(int? percent) {
    if (percent == null) return Icons.battery_unknown_rounded;
    if (percent >= 80) return Icons.battery_full_rounded;
    if (percent >= 40) return Icons.battery_5_bar_rounded;
    if (percent >= 15) return Icons.battery_2_bar_rounded;
    return Icons.battery_alert_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final permissions = context.watch<PermissionsProvider>();
    final deviceState = context.watch<DeviceProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: Builder(builder: (context) {
        if (permissions.isLoading) return const LoadingView();
        if (!permissions.permissions.device) {
          return const PermissionLockedView(category: 'Device status');
        }
        if (deviceState.isLoading && deviceState.devices.isEmpty) return const LoadingView();
        if (deviceState.error != null && deviceState.devices.isEmpty) {
          return ErrorView(message: deviceState.error!.message, onRetry: _load);
        }
        if (deviceState.devices.isEmpty) {
          return const EmptyState(icon: Icons.watch_off_outlined, title: 'No devices connected yet');
        }
        return RefreshIndicator(
          onRefresh: () async => _load(),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: deviceState.devices.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final device = deviceState.devices[i];
              final connected = device.connectionState == DeviceConnectionState.connected;
              return SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(device.name, style: Theme.of(context).textTheme.titleMedium)),
                        StatusIndicator(
                          level: connected ? StatusLevel.normal : StatusLevel.attention,
                          label: connected ? 'Connected' : 'Disconnected',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (device.batteryPercent != null)
                      Row(
                        children: [
                          Icon(_batteryIcon(device.batteryPercent), size: 20, color: Theme.of(context).textTheme.bodyMedium?.color),
                          const SizedBox(width: 8),
                          Text('${device.batteryPercent}%', style: Theme.of(context).textTheme.bodyLarge),
                        ],
                      ),
                    const SizedBox(height: 10),
                    LastUpdatedLabel(time: device.lastSyncedAt),
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
