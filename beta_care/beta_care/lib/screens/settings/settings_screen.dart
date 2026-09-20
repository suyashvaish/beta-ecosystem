import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../devices/devices_screen.dart';
import '../family/family_screen.dart';
import 'notification_settings_screen.dart';
import 'permissions_privacy_screen.dart';
import 'profile_screen.dart';

/// Section 17. A flat, readable menu - nothing here needs more than one tap
/// to reach.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _showInfoDialog(BuildContext context, {required String title, required List<String> points}) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: points.map((p) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('•  $p'))).toList(),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AuthProvider>().signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(leading: const Icon(Icons.person_outline_rounded), title: const Text('Account'), onTap: () => _push(context, const ProfileScreen())),
          ListTile(leading: const Icon(Icons.people_outline_rounded), title: const Text('Family'), onTap: () => _push(context, const FamilyScreen())),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Permissions & Privacy'),
            onTap: () => _push(context, const PermissionsPrivacyScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            onTap: () => _push(context, const NotificationSettingsScreen()),
          ),
          ListTile(leading: const Icon(Icons.watch_outlined), title: const Text('Connected Devices'), onTap: () => _push(context, const DevicesScreen())),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Security'),
            onTap: () => _showInfoDialog(
              context,
              title: 'Security',
              points: const [
                'Your account uses Firebase Authentication, separate from the elderly person you care for.',
                'All requests to Beta are made over HTTPS.',
                'This app never stores database credentials or the elderly account\'s private data.',
                'Access to sensitive information is checked by the Beta backend on every request.',
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: const Text('Help'),
            onTap: () => _showInfoDialog(
              context,
              title: 'Help',
              points: const [
                'Ask the elderly person to open their Beta AI app to approve a connection or change what you can see.',
                'If something looks out of date, pull down to refresh on any screen.',
                'Contact support@example.com for anything else.',
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout_rounded, color: Theme.of(context).colorScheme.error),
            title: Text('Log out', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () => _confirmSignOut(context),
          ),
        ],
      ),
    );
  }
}
