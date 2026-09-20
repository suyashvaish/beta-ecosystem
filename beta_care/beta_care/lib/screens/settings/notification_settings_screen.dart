import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/notification_settings_provider.dart';
import '../../widgets/common_widgets.dart';

/// Sections 9 & 13. Emergency alerts are shown but not editable - every
/// other category can be muted, emergencies never are.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<NotificationSettingsProvider>().load());
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<NotificationSettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: Builder(builder: (context) {
        if (settings.isLoading) return const LoadingView();
        if (settings.error != null) {
          return ErrorView(message: settings.error!.message, onRetry: () => context.read<NotificationSettingsProvider>().load());
        }
        final prefs = settings.preferences;
        return ListView(
          children: [
            SwitchListTile(
              title: const Text('Medication alerts'),
              subtitle: const Text('When a dose is confirmed or goes unconfirmed'),
              value: prefs.medicationAlerts,
              onChanged: (v) => context.read<NotificationSettingsProvider>().update(prefs.copyWith(medicationAlerts: v)),
            ),
            SwitchListTile(
              title: const Text('Health alerts'),
              subtitle: const Text('When a reading is outside the configured range'),
              value: prefs.healthAlerts,
              onChanged: (v) => context.read<NotificationSettingsProvider>().update(prefs.copyWith(healthAlerts: v)),
            ),
            SwitchListTile(
              title: const Text('Device alerts'),
              subtitle: const Text('When the health band disconnects'),
              value: prefs.deviceAlerts,
              onChanged: (v) => context.read<NotificationSettingsProvider>().update(prefs.copyWith(deviceAlerts: v)),
            ),
            SwitchListTile(
              title: const Text('Location alerts'),
              subtitle: const Text('When location sharing changes'),
              value: prefs.locationAlerts,
              onChanged: (v) => context.read<NotificationSettingsProvider>().update(prefs.copyWith(locationAlerts: v)),
            ),
            const SwitchListTile(
              title: Text('Emergency alerts'),
              subtitle: Text("Can't be turned off"),
              value: true,
              onChanged: null,
            ),
          ],
        );
      }),
    );
  }
}
