import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/family_provider.dart';
import '../providers/permissions_provider.dart';
import '../screens/alerts/alerts_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/family/add_elderly_screen.dart';
import '../screens/health/health_screen.dart';
import '../screens/medications/medications_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../widgets/common_widgets.dart';

/// Everything after sign-in lives here. Before showing the five monitoring
/// tabs, this loads the caregiver's family connections and - once there's
/// an active one - their permissions for it, so every tab can assume both
/// are already available by the time it mounts (see the tab screens'
/// `_load()` methods, which just read [FamilyProvider.primaryElderlyUserId]
/// directly rather than re-checking for null every time).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _tabs = [
    DashboardScreen(),
    MedicationsScreen(),
    HealthScreen(),
    AlertsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(_bootstrap);
  }

  Future<void> _bootstrap() async {
    final family = context.read<FamilyProvider>();
    await family.load();
    if (!mounted) return;
    final id = family.primaryElderlyUserId;
    if (id != null) {
      context.read<PermissionsProvider>().load(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final family = context.watch<FamilyProvider>();

    if (family.isLoading && family.links.isEmpty) {
      return const Scaffold(body: LoadingView());
    }

    if (family.error != null && family.links.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Beta Care')),
        body: ErrorView(message: family.error!.message, onRetry: family.load),
      );
    }

    if (family.activeLinks.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Beta Care')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite_rounded, size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text('Connect to get started', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  "Add the elderly family member you're caring for using their invitation code.",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddElderlyScreen())),
                  child: const Text('Add elderly connection'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.medication_outlined), selectedIcon: Icon(Icons.medication_rounded), label: 'Meds'),
          NavigationDestination(icon: Icon(Icons.favorite_outline_rounded), selectedIcon: Icon(Icons.favorite_rounded), label: 'Health'),
          NavigationDestination(icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications_rounded), label: 'Alerts'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}
