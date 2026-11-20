import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/family_talk_api_service.dart';

/// Caregiver's home: pick which elder's conversation to open.
///
/// With one elder this pushes straight into the thread (the normal
/// case); with several it shows the list first.
class ElderPickerScreen extends StatefulWidget {
  const ElderPickerScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<ElderPickerScreen> createState() => _ElderPickerScreenState();
}

class _ElderPickerScreenState extends State<ElderPickerScreen> {
  late final FamilyTalkApiService _api;
  bool _loading = true;
  String? _error;
  String? _myUserId;
  List<MyElder> _elders = const [];

  @override
  void initState() {
    super.initState();
    _api = FamilyTalkApiService(authService: widget.authService);
    _load();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      BackendConfig.requireConfigured();
      final myId = await _api.myUserId();
      final elders = await _api.myElders();
      if (!mounted) return;
      setState(() {
        _myUserId = myId;
        _elders = elders;
        _loading = false;
      });

      // One elder: go straight to the conversation.
      if (elders.length == 1) {
        _openTalk(elders.first);
      }
    } on FamilyTalkApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load: $e';
        _loading = false;
      });
    }
  }

  void _openTalk(MyElder elder) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FamilyTalkScreen(
          api: _api,
          elderUserId: elder.elderUserId,
          myUserId: _myUserId!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08091D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF08091D),
        title: const Text(
          'Beta Care',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white70),
            tooltip: 'Sign out',
            onPressed: () => widget.authService.signOut(),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_elders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.family_restroom_rounded,
                  color: Colors.white24, size: 64),
              SizedBox(height: 16),
              Text(
                'No elder in your care yet',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              SizedBox(height: 8),
              Text(
                'Ask your elder\'s Beta app to send you an invite code, '
                'or add yourself to their care circle.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _elders.length,
      itemBuilder: (context, index) {
        final elder = _elders[index];
        return ListTile(
          leading: const Icon(Icons.person_rounded, color: Colors.white70),
          title:
              Text(elder.elderUserId, style: const TextStyle(color: Colors.white)),
          subtitle: Text(elder.circleRole,
              style: const TextStyle(color: Colors.white54)),
          onTap: () => _openTalk(elder),
        );
      },
    );
  }
}