import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../services/family_talk_api_service.dart';

/// Walkie-talkie thread with one elder (Feature C UI, caregiver side).
///
/// Hold the mic to record; release to upload + send. Same backend
/// endpoints as the elder's Beta Asli app - authorization is circle
/// membership, enforced server-side.
class FamilyTalkScreen extends StatefulWidget {
  const FamilyTalkScreen({
    super.key,
    required this.api,
    required this.elderUserId,
    required this.myUserId,
  });

  final FamilyTalkApiService api;
  final String elderUserId;
  final String myUserId;

  @override
  State<FamilyTalkScreen> createState() => _FamilyTalkScreenState();
}

class _FamilyTalkScreenState extends State<FamilyTalkScreen> {
  bool _loading = true;
  String? _error;
  final List<FamilyMessage> _messages = <FamilyMessage>[];

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _recordStart;
  bool _sending = false;

  final AudioPlayer _player = AudioPlayer();
  String? _playingId;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final messages = await widget.api.history(widget.elderUserId);

      for (final m in messages) {
        if (!m.read && m.senderUserId != widget.myUserId) {
          try {
            await widget.api.markRead(
                elderUserId: widget.elderUserId, messageId: m.id);
          } catch (_) {}
        }
      }

      if (!mounted) return;
      setState(() {
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
        _error = 'Could not load messages: $e';
        _loading = false;
      });
    }
  }

  Future<void> _sendText() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    _inputController.clear();
    setState(() => _sending = true);
    try {
      final message = await widget.api
          .sendText(elderUserId: widget.elderUserId, text: text);
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

  Future<void> _startRecording() async {
    if (_sending) return;

    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _showSnack(
          'Microphone access is blocked. Enable it in device settings.');
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
        DateTime.now().difference(_recordStart!).inSeconds + 1;
    _recordStart = null;

    final path = await _recorder.stop();
    if (path == null) return;
    if (!mounted) return;
    setState(() => _sending = true);

    try {
      final audioUrl = await widget.api.uploadVoiceNote(
        elderUserId: widget.elderUserId,
        audioFile: File(path),
        durationSeconds: duration,
      );
      final message = await widget.api.sendVoice(
        elderUserId: widget.elderUserId,
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

  Future<void> _playMessage(FamilyMessage message) async {
    if (_playingId == message.id) {
      await _player.stop();
      if (mounted) setState(() => _playingId = null);
      return;
    }
    try {
      final uri = widget.api.playbackUri(message);
      final headers = await widget.api.playbackHeaders();
      await _player.setAudioSource(
        AudioSource.uri(uri, headers: headers),
      );
      await _player.play();
      if (mounted) setState(() => _playingId = message.id);
    } catch (e) {
      _showSnack('Could not play: $e');
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final bool recording = _recordStart != null;

    return Scaffold(
      backgroundColor: const Color(0xFF08091D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF08091D),
        title: const Text(
          'Family Talk',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
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
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          'Hold the mic to send your elder a voice note',
          style: TextStyle(color: Colors.white70, fontSize: 15),
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
    final bool mine = m.senderUserId == widget.myUserId;
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
          color: mine
              ? const Color(0xFF8755FF)
              : const Color(0xFF101329),
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
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            if (isVoice)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _playingId == m.id
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                    color: mine ? Colors.black : Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text('${m.durationSeconds ?? 0}s',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14)),
                ],
              )
            else
              Text(m.body ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 15)),
            if (isVoice && (m.transcript?.isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  m.transcript!,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
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
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: recording ? 'Recording...' : 'Type a message...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 15),
                filled: true,
                fillColor: const Color(0xFF101329),
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
                    ? const Color(0xFFFF7A8A)
                    : const Color(0xFF8755FF),
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