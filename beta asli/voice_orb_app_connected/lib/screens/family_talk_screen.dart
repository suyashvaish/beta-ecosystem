import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../services/auth_service.dart';
import '../services/family_talk_api_service.dart';
import '../theme/beta_theme.dart';

/// Family Talk - the walkie-talkie screen (Feature C UI).
///
/// Hold the mic button to record a voice note; release to upload and
/// send it to the family circle. Text messages work too. Voice notes
/// from family members play through the backend's authorized playback
/// endpoint (never a public URL).
class FamilyTalkScreen extends StatefulWidget {
  const FamilyTalkScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<FamilyTalkScreen> createState() => _FamilyTalkScreenState();
}

class _FamilyTalkScreenState extends State<FamilyTalkScreen> {
  late final FamilyTalkApiService _api;

  bool _loading = true;
  String? _error;
  String? _elderUserId;
  String? _myUserId;
  final List<FamilyMessage> _messages = <FamilyMessage>[];

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Recording
  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _recordStart;
  bool _sending = false;
  String? _recordingError;

  // Playback
  final AudioPlayer _player = AudioPlayer();
  String? _playingId;

  @override
  void initState() {
    super.initState();
    _api = FamilyTalkApiService(authService: widget.authService);

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
      final profile = await _api.myProfile();
      final elderId = await _api.resolveElderUserId();
      final messages = await _api.history(elderId);

      // Mark incoming messages read as we open the thread.
      for (final m in messages) {
        if (!m.read && m.senderUserId != profile.userId) {
          try {
            await _api.markRead(elderUserId: elderId, messageId: m.id);
          } catch (_) {}
        }
      }

      if (!mounted) return;
      setState(() {
        _myUserId = profile.userId;
        _elderUserId = elderId;
        _messages
          ..clear()
          ..addAll(messages);
        _loading = false;
      });
      _scrollToBottom();
    } on FamilyTalkApiException catch (e) {
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
    } on FamilyTalkApiException catch (e) {
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
    setState(() => _recordingError = null);

    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      setState(() => _recordingError =
          'Microphone access is blocked. Enable it for Beta in device settings.');
      _showSnack(_recordingError!);
      return;
    }

    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path:
            '${Directory.systemTemp.path}/family_note_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
      setState(() => _recordStart = DateTime.now());
    } catch (e) {
      setState(() => _recordingError = 'Could not start recording: $e');
      _showSnack(_recordingError!);
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
    } on FamilyTalkApiException catch (e) {
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

  Future<void> _playMessage(FamilyMessage message) async {
    if (_playingId == message.id) {
      await _player.stop();
      if (mounted) setState(() => _playingId = null);
      return;
    }
    try {
      final uri = await _api.playbackUri(message);
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

    return Scaffold(
      backgroundColor: BetaColors.background,
      appBar: AppBar(
        backgroundColor: BetaColors.background,
        title: Text('Family Talk', style: BetaText.greetingSub),
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
                style:
                    BetaText.body.copyWith(color: BetaColors.textSecondary),
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
          'Hold the mic to send your family a voice note',
          style: BetaText.body.copyWith(color: BetaColors.textSecondary),
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

  Widget _buildBubble(FamilyMessage m) {
    final bool mine = m.senderUserId == _myUserId;
    final bool isVoice = m.messageType == 'voice';

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: mine ? BetaColors.purple : BetaColors.backgroundSecondary,
          // BetaColors.accent does not exist in the palette; the accent
          // is `purple`. My bubbles use the purple->pink pill gradient
          // to match the mic button's visual language.
          gradient: mine ? BetaColors.pillGradient : null,
          color: mine ? null : BetaColors.backgroundSecondary,
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
                style: BetaText.status.copyWith(fontSize: 11),
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
                        color: mine ? Colors.black : BetaColors.textPrimary,
                      ),
                      const SizedBox(width: 4),
                      Text('${m.durationSeconds ?? 0}s'),
                    ],
                  ),
                ),
              )
            else
              Text(m.body ?? '', style: BetaText.body),
            if (isVoice && (m.transcript?.isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  m.transcript!,
                  style:
                      BetaText.status.copyWith(color: BetaColors.textSecondary),
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
              style: BetaText.body,
              decoration: InputDecoration(
                hintText: recording ? 'Recording...' : 'Type a message...',
                hintStyle: const TextStyle(
                  color: BetaColors.textSecondary,
                  fontSize: 15,
                ),
                filled: true,
                fillColor: BetaColors.backgroundSecondary,
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
                color: recording ? Colors.red : BetaColors.purple,
                // BetaColors.accent does not exist; use the signature
                // mic gradient instead.
                gradient: BetaColors.micGradient,
                shape: BoxShape.circle,
              ),
              child: Icon(
                recording ? Icons.stop_rounded : Icons.mic_rounded,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}