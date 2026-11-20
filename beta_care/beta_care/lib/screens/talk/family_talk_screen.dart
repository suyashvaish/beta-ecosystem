import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../providers/family_provider.dart';
import '../../services/auth_service.dart';
import '../../services/family_talk_service.dart';

/// Family Talk tab - the walkie-talkie with the elder's Beta Asli app.
///
/// Hold the mic button to record a voice note; release to upload and
/// send. Text messages work too. Tapping a voice bubble plays it via
/// the backend's authorized endpoint (auth header required, so a leaked
/// URL alone can never play anything).
class FamilyTalkScreen extends StatefulWidget {
  const FamilyTalkScreen({super.key});

  @override
  State<FamilyTalkScreen> createState() => _FamilyTalkScreenState();
}

class _FamilyTalkScreenState extends State<FamilyTalkScreen> {
  late final FamilyTalkService _api;

  bool _loading = true;
  String? _error;
  String? _elderUserId;
  String? _myUserId;
  final List<FamilyTalkMessage> _messages = <FamilyTalkMessage>[];

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Recording
  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _recordStart;
  bool _sending = false;

  // Playback
  final AudioPlayer _player = AudioPlayer();
  String? _playingId;

  @override
  void initState() {
    super.initState();
    _api = FamilyTalkService(
        authService: context.read<AuthService>());

    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (mounted) setState(() => _playingId = null);
      }
    });

    _load();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    unawaited(_player.dispose());
    unawaited(_recorder.dispose());
    _api.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Load
  // ------------------------------------------------------------------

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final myId = await _api.myUserId();
      final elders = await _api.myElders();
      if (elders.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = 'No family connection yet. Ask for an invite code from '
              'the Beta Asli app.';
          _loading = false;
        });
        return;
      }
      final elderId = elders.first;
      final messages = await _api.history(elderId);

      // Mark incoming messages read as we open the thread.
      for (final m in messages) {
        if (!m.read && m.senderUserId != myId) {
          try {
            await _api.markRead(elderUserId: elderId, messageId: m.id);
          } catch (_) {}
        }
      }

      if (!mounted) return;
      setState(() {
        _myUserId = myId;
        _elderUserId = elderId;
        _messages
          ..clear()
          ..addAll(messages);
        _loading = false;
      });
      _scrollToBottom();
    } on FamilyTalkException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load Family Talk: $e';
        _loading = false;
      });
    }
  }

  // ------------------------------------------------------------------
  // Send text
  // ------------------------------------------------------------------

  Future<void> _sendText() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _elderUserId == null || _sending) return;

    _inputController.clear();
    setState(() => _sending = true);
    try {
      final message =
          await _api.sendText(elderUserId: _elderUserId!, text: text);
      if (!mounted) return;
      setState(() {
        _messages.add(message);
        _sending = false;
      });
      _scrollToBottom();
    } on FamilyTalkException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _showSnack(e.message);
    }
  }

  // ------------------------------------------------------------------
  // Walkie-talkie: hold to record, release to send
  // ------------------------------------------------------------------

  Future<void> _startRecording() async {
    if (_elderUserId == null || _sending) return;

    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _showSnack('Microphone access is blocked. Enable it for Beta Care '
          'in device settings.');
      return;
    }

    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path:
            '${Directory.systemTemp.path}/care_note_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
      setState(() => _recordStart = DateTime.now());
    } catch (e) {
      _showSnack('Could not start recording: $e');
    }
  }

  Future<void> _finishRecording() async {
    if (_recordStart == null) return;
    final duration =
        DateTime.now().difference(_recordStart!).inSeconds + 1; // min 1s
    _recordStart = null;

    final path = await _recorder.stop();
    if (path == null) return;
    if (!mounted) return;
    setState(() => _sending = true);

    try {
      final audioUrl = await _api.uploadVoiceNote(
        elderUserId: _elderUserId!,
        audioFile: File(path),
        durationSeconds: duration,
      );
      final message = await _api.sendVoice(
        elderUserId: _elderUserId!,
        audioUrl: audioUrl,
        durationSeconds: duration,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(message);
        _sending = false;
      });
      _scrollToBottom();
    } on FamilyTalkException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _showSnack(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _showSnack('Could not send voice note: $e');
    }
  }

  // ------------------------------------------------------------------
  // Playback
  // ------------------------------------------------------------------

  Future<void> _playMessage(FamilyTalkMessage message) async {
    if (_playingId == message.id) {
      await _player.stop();
      if (mounted) setState(() => _playingId = null);
      return;
    }
    try {
      final uri = _api.playbackUri(message);
      final headers = await _api.playbackHeaders();
      await _player.setAudioSource(
        AudioSource.uri(uri, headers: headers),
      );
      await _player.play();
      if (mounted) setState(() => _playingId = message.id);
    } catch (e) {
      _showSnack('Could not play: $e');
    }
  }

  // ------------------------------------------------------------------
  // UI helpers
  // ------------------------------------------------------------------

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool recording = _recordStart != null;
    final family = context.watch<FamilyProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Talk to ${family.primaryLink?.elderlyUser.displayName ?? "family"}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildBody()),
            _buildComposer(recording),
          ],
        ),
      ),
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
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          'Hold the mic to send a voice note',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) => _buildBubble(_messages[index]),
    );
  }

  Widget _buildBubble(FamilyTalkMessage m) {
    final bool mine = m.senderUserId == _myUserId;
    final bool isVoice = m.messageType == 'voice';
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: mine ? colorScheme.primary : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!mine)
              Text(
                m.senderName,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            if (isVoice)
              // Tap the bubble to play / stop the voice note.
              InkWell(
                onTap: () => _playMessage(m),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _playingId == m.id
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                        color: mine
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                      ),
                      const SizedBox(width: 4),
                      Text('${m.durationSeconds ?? 0}s'),
                    ],
                  ),
                ),
              )
            else
              Text(m.body ?? ''),
            if (isVoice && (m.transcript?.isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  m.transcript!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer(bool recording) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              onSubmitted: (_) => _sendText(),
              textInputAction: TextInputAction.send,
              enabled: !_sending,
              decoration: InputDecoration(
                hintText: recording ? 'Recording...' : 'Type a message...',
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(27),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onLongPressStart: (_) => _startRecording(),
            onLongPressEnd: (_) => _finishRecording(),
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: recording
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                recording ? Icons.stop_rounded : Icons.mic_rounded,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
