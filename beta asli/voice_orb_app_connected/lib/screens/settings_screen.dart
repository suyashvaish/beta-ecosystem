import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/auth_service.dart';
import '../services/settings_service.dart';

/// Full settings screen, reachable from the gear icon on the home page.
///
/// Every field reads its initial value from [SettingsService] and writes
/// straight back through it (which persists via SharedPreferences), so
/// there's no separate "Save" step — values stick immediately and are
/// reloaded automatically the next time the app launches.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService.instance;

  late final _backendUrlController =
      TextEditingController(text: _settings.backendUrl);
  late final _aiModelController =
      TextEditingController(text: _settings.aiModel);
  late final _wakeWordController =
      TextEditingController(text: _settings.wakeWord);

  bool _clearingMemory = false;

  @override
  void dispose() {
    _backendUrlController.dispose();
    _aiModelController.dispose();
    _wakeWordController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _section('Connection'),
          _textTile(
            title: 'Backend URL',
            controller: _backendUrlController,
            hint: 'http://192.168.1.22:8000',
            keyboardType: TextInputType.url,
            onChanged: _settings.setBackendUrl,
          ),
          _textTile(
            title: 'AI Model',
            controller: _aiModelController,
            hint: SettingsService.defaultAiModel,
            onChanged: _settings.setAiModel,
          ),
          _section('Voice'),
          _pickerTile(
            title: 'Voice Selection',
            value: _settings.voice,
            options: const ['Default', 'Alloy', 'Echo', 'Fable', 'Onyx', 'Nova', 'Shimmer'],
            onSelected: (v) async {
              await _settings.setVoice(v);
              _refresh();
            },
          ),
          _textTile(
            title: 'Wake Word',
            controller: _wakeWordController,
            hint: 'Beta',
            onChanged: _settings.setWakeWord,
          ),
          _sliderTile(
            title: 'Speech Speed',
            value: _settings.speechSpeed,
            min: 0.5,
            max: 2.0,
            label: '${_settings.speechSpeed.toStringAsFixed(2)}x',
            onChanged: (v) async {
              await _settings.setSpeechSpeed(v);
              _refresh();
            },
          ),
          _switchTile(
            title: 'Auto Speak',
            subtitle: 'Speak assistant replies automatically',
            value: _settings.autoSpeakEnabled,
            onChanged: (v) async {
              await _settings.setAutoSpeakEnabled(v);
              _refresh();
            },
          ),
          _sliderTile(
            title: 'Microphone Sensitivity',
            value: _settings.micSensitivity,
            min: 0.0,
            max: 1.0,
            label: '${(_settings.micSensitivity * 100).round()}%',
            onChanged: (v) async {
              await _settings.setMicSensitivity(v);
              _refresh();
            },
          ),
          _section('Appearance'),
          _pickerTile(
            title: 'Theme',
            value: switch (_settings.themeMode) {
              AppThemeMode.system => 'System',
              AppThemeMode.light => 'Light',
              AppThemeMode.dark => 'Dark',
            },
            options: const ['System', 'Light', 'Dark'],
            onSelected: (v) async {
              final mode = switch (v) {
                'System' => AppThemeMode.system,
                'Light' => AppThemeMode.light,
                _ => AppThemeMode.dark,
              };
              await _settings.setThemeMode(mode);
              _refresh();
            },
          ),
          _section('Privacy & Notifications'),
          _switchTile(
            title: 'Notifications',
            value: _settings.notificationsEnabled,
            onChanged: (v) async {
              await _settings.setNotificationsEnabled(v);
              _refresh();
            },
          ),
          _switchTile(
            title: 'Conversation Memory',
            subtitle: "Let Beta remember details across conversations",
            value: _settings.conversationMemoryEnabled,
            onChanged: (v) async {
              await _settings.setConversationMemoryEnabled(v);
              _refresh();
            },
          ),
          _section('Data'),
          _actionTile(
            title: 'Clear Conversation History',
            icon: Icons.delete_sweep_outlined,
            onTap: _confirmClearConversationHistory,
          ),
          _actionTile(
            title: 'Clear Memory',
            icon: Icons.psychology_alt_outlined,
            trailing: _clearingMemory
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _clearingMemory ? null : _confirmClearMemory,
          ),
          _section('About'),
          const _AboutTile(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------
  // Actions
  // -----------------------------------------------------------------

  Future<void> _confirmClearConversationHistory() async {
    final confirmed = await _confirm(
      title: 'Clear conversation history?',
      message: 'This clears what\'s shown on this device. '
          'It does not delete conversations already saved on the server.',
    );
    if (!confirmed || !mounted) return;
    // No local conversation cache exists yet (history lives server-side
    // via ConversationRepository, with no bulk-delete endpoint) — this
    // is the hook point for when local caching is added.
    await _settings.clearConversationHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Conversation history cleared on this device.')),
    );
  }

  Future<void> _confirmClearMemory() async {
    final confirmed = await _confirm(
      title: 'Clear all memory?',
      message: 'Beta will forget everything it has learned about you. '
          'This cannot be undone.',
    );
    if (!confirmed || !mounted) return;

    setState(() => _clearingMemory = true);
    try {
      await _clearAllMemoriesOnBackend();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Memory cleared.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clear memory: $e')),
      );
    } finally {
      if (mounted) setState(() => _clearingMemory = false);
    }
  }

  /// Uses the existing `GET /memories` + `DELETE /memories/{id}` endpoints
  /// (there's no bulk-delete endpoint on the backend) to remove everything.
  Future<void> _clearAllMemoriesOnBackend() async {
    final token = await widget.authService.idToken;
    if (token == null) {
      throw Exception('Not signed in.');
    }
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    final listResponse = await http
        .get(Uri.parse('${_settings.backendApiV1}/memories'), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (listResponse.statusCode >= 400) {
      throw Exception('Server error (${listResponse.statusCode})');
    }

    final memories = jsonDecode(listResponse.body) as List<dynamic>;
    for (final memory in memories) {
      final id = (memory as Map<String, dynamic>)['id'];
      if (id == null) continue;
      await http
          .delete(
            Uri.parse('${_settings.backendApiV1}/memories/$id'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));
    }
  }

  Future<bool> _confirm({required String title, required String message}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // -----------------------------------------------------------------
  // Reusable row builders
  // -----------------------------------------------------------------

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _textTile({
    required String title,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    String? hint,
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            onChanged: onChanged,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: const Color(0xFF1C1C1E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? subtitle,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12))
          : null,
    );
  }

  Widget _sliderTile({
    required String title,
    required double value,
    required double min,
    required double max,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
              Text(label, style: const TextStyle(color: Colors.white38, fontSize: 13)),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            activeColor: Colors.white,
            inactiveColor: Colors.white24,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _pickerTile({
    required String title,
    required String value,
    required List<String> options,
    required ValueChanged<String> onSelected,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: const TextStyle(color: Colors.white38, fontSize: 14)),
          const Icon(Icons.chevron_right, color: Colors.white24),
        ],
      ),
      onTap: () async {
        final selected = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: const Color(0xFF1C1C1E),
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: options
                  .map(
                    (o) => ListTile(
                      title: Text(o, style: const TextStyle(color: Colors.white)),
                      trailing: o == value
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                      onTap: () => Navigator.of(context).pop(o),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
        if (selected != null) onSelected(selected);
      },
    );
  }

  Widget _actionTile({
    required String title,
    required IconData icon,
    required VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(icon, color: Colors.redAccent),
      title: Text(title, style: const TextStyle(color: Colors.redAccent, fontSize: 15)),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _AboutTile extends StatelessWidget {
  const _AboutTile();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Beta', style: TextStyle(color: Colors.white, fontSize: 15)),
          SizedBox(height: 4),
          Text(
            'Version 1.0.0',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
