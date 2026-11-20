import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../services/auth_service.dart';
import '../services/chat_api_service.dart';
import '../services/voice_controller.dart';
import '../theme/beta_theme.dart';
import '../widgets/audio_waveform.dart';
import '../widgets/beta_buttons.dart';
import '../widgets/chat_message_bubble.dart';
import 'settings_screen.dart';

/// The redesigned Beta home experience.
///
/// Three visual states (from the reference design):
///   1. HOME / greeting - "Good Day / How can I help?" with the
///      "Ask anything..." input.
///   2. VOICE - layered waveform replacing the old orb, driven by REAL
///      mic dB levels from VoiceController, with the stop button.
///   3. CHAT - the conversation list (now actually rendered - the old
///      page showed only a single caption), reusing ChatApiService
///      streaming underneath.
///
/// All voice/chat logic is delegated to VoiceController and
/// ChatApiService - this screen only maps their events to UI state,
/// exactly like the previous implementation did (see VOICE_FIXES.md).
class VoiceHomePage extends StatefulWidget {
  const VoiceHomePage({super.key, required this.authService});

  final AuthService authService;

  @override
  State<VoiceHomePage> createState() => _VoiceHomePageState();
}

class _VoiceHomePageState extends State<VoiceHomePage> {
  // =========================================================================
  // STATE
  // =========================================================================

  /// Real-time 0..1 mic level. A ValueNotifier so high-frequency level
  /// updates repaint the waveform without rebuilding the whole screen.
  final ValueNotifier<double> _audioLevel = ValueNotifier<double>(0.0);

  _AssistantState _state = _AssistantState.idle;

  late final ChatApiService _chatApi;
  String? _conversationId;
  StreamSubscription<ChatStreamEvent>? _streamSub;

  /// The conversation list. Previously the home page rendered only a
  /// single caption; the redesign shows the actual turns.
  final List<ChatMessage> _messages = <ChatMessage>[];

  String? _lastUserMessage;
  bool _messageBeingSent = false;

  late final VoiceController _voice;

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // =========================================================================
  // INIT / DISPOSE
  // =========================================================================

  @override
  void initState() {
    super.initState();

    _chatApi = ChatApiService(authService: widget.authService);

    _inputController.addListener(_onTextChanged);

    _voice = VoiceController(
      onStateChanged: _onVoiceStateChanged,
      onLevelChanged: (level) => _audioLevel.value = level,
      onPartialTranscript: _onPartialTranscript,
      onFinalTranscript: _onFinalTranscript,
      onError: _onVoiceError,
    );
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _inputController.removeListener(_onTextChanged);
    _inputController.dispose();
    _scrollController.dispose();
    _audioLevel.dispose();
    // Fire-and-forget: the controller stops STT/TTS and cleans up; no
    // UI remains to await the result.
    unawaited(_voice.dispose());
    _chatApi.dispose();
    super.dispose();
  }

  // =========================================================================
  // TEXT FIELD
  // =========================================================================

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {});
  }

  // =========================================================================
  // VOICE CALLBACKS
  // =========================================================================

  void _onVoiceStateChanged(VoiceState state) {
    if (!mounted) return;

    setState(() {
      switch (state) {
        case VoiceState.idle:
        case VoiceState.listening:
          _state = _AssistantState.idle;
        case VoiceState.processing:
          _state = _AssistantState.thinking;
        case VoiceState.speaking:
          _state = _AssistantState.speaking;
        case VoiceState.error:
          _state = _AssistantState.error;
      }
    });
  }

  void _onPartialTranscript(String transcript) {
    if (!mounted) return;

    _inputController.value = TextEditingValue(
      text: transcript,
      selection: TextSelection.collapsed(offset: transcript.length),
    );

    setState(() {});
  }

  void _onFinalTranscript(String transcript) {
    _sendMessage(text: transcript, viaVoice: true);
  }

  void _onVoiceError(String message) {
    if (!mounted) return;

    setState(() {
      if (_messages.isNotEmpty &&
          _messages.last.role == ChatRole.assistant &&
          _messages.last.status == ChatMessageStatus.streaming) {
        _messages.last
          ..text = message
          ..status = ChatMessageStatus.error;
      }
    });
  }

  // =========================================================================
  // SEND MESSAGE (same flow as before, now also appends to the list)
  // =========================================================================

  Future<void> _sendMessage({String? text, bool viaVoice = false}) async {
    final String message = (text ?? _inputController.text).trim();

    if (message.isEmpty) return;
    if (_messageBeingSent) return;

    // A voice-finalized send is initiated by the controller (mic closed,
    // no request in flight), and the controller reports state=processing
    // BEFORE invoking onFinalTranscript - so the busy guard would reject
    // the very send it triggers. Only typed input is blocked while busy.
    if (!viaVoice &&
        (_state == _AssistantState.thinking ||
            _state == _AssistantState.speaking)) {
      return;
    }

    _messageBeingSent = true;

    try {
      // Make sure the microphone is closed while the request streams in.
      await _voice.stopListening();

      try {
        await _streamSub?.cancel();
      } catch (_) {}
      _streamSub = null;

      if (!mounted) return;

      _lastUserMessage = message;

      if (!viaVoice) _inputController.clear();

      final int stamp = DateTime.now().millisecondsSinceEpoch;

      setState(() {
        _state = _AssistantState.thinking;

        _messages.add(ChatMessage(
          id: 'user-$stamp',
          role: ChatRole.user,
          text: message,
          viaVoice: viaVoice,
        ));

        // Placeholder assistant turn: streaming status renders the
        // typing indicator until the first chunk arrives.
        _messages.add(ChatMessage(
          id: 'beta-$stamp',
          role: ChatRole.assistant,
          text: '',
          status: ChatMessageStatus.streaming,
        ));
      });

      _scrollToBottom();

      _streamSub = _chatApi
          .sendMessageStream(
            message: message,
            conversationId: _conversationId,
          )
          .listen(
        (event) {
          if (!mounted) return;

          switch (event) {
            case ChatConversationStarted():
              _conversationId = event.conversationId;

            case ChatTextChunk():
              if (event.text.isEmpty) return;

              setState(() {
                _state = _AssistantState.speaking;
                _messages.last.text += event.text;
              });

              _scrollToBottom();

            case ChatStreamDone():
              final String response = _messages.last.text.trim();

              if (response.isEmpty) {
                setState(() {
                  _messages.removeLast();
                  _state = _AssistantState.idle;
                });
                return;
              }

              setState(() {
                _messages.last.status = ChatMessageStatus.complete;
              });

              unawaited(
                _speakAssistantResponse(response, viaVoice: viaVoice),
              );

            case ChatStreamError():
              setState(() {
                _state = _AssistantState.error;
                _messages.last
                  ..text = event.detail
                  ..status = ChatMessageStatus.error;
              });
          }
        },
        onError: (Object error) {
          if (!mounted) return;

          setState(() {
            _state = _AssistantState.error;
            _messages.last
              ..text = 'Unable to contact Beta.'
              ..status = ChatMessageStatus.error;
          });
        },
        onDone: () {
          _streamSub = null;
        },
        cancelOnError: false,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _state = _AssistantState.error;
        _messages.last
          ..text = 'Unable to contact Beta.'
          ..status = ChatMessageStatus.error;
      });
    } finally {
      _messageBeingSent = false;
    }
  }

  Future<void> _sendTypedMessage() async {
    final String text = _inputController.text.trim();
    if (text.isEmpty) return;

    await _sendMessage(text: text, viaVoice: false);
  }

  // =========================================================================
  // TTS (delegates to the fixed VoiceController)
  // =========================================================================

  Future<void> _speakAssistantResponse(
    String text, {
    required bool viaVoice,
  }) async {
    if (text.trim().isEmpty) {
      if (!mounted) return;
      setState(() => _state = _AssistantState.idle);
      return;
    }

    final bool spoke = await _voice.speak(text);

    if (!mounted) return;

    if (!spoke) {
      setState(() => _state = _AssistantState.error);
      return;
    }

    if (viaVoice) {
      // Re-arm the hands-free loop; the controller handles audio focus
      // handover before it opens the microphone.
      await _voice.startListening(handsFree: true);
    } else {
      setState(() => _state = _AssistantState.idle);
    }
  }

  // =========================================================================
  // MIC TAP
  // =========================================================================

  Future<void> _onMicTap() async {
    if (_voice.isListening) {
      await _voice.stopListening();
      return;
    }

    switch (_state) {
      case _AssistantState.idle:
        await _voice.startListening(handsFree: true);
      case _AssistantState.thinking:
        try {
          await _streamSub?.cancel();
        } catch (_) {}
        _streamSub = null;
        await _voice.stopListening();
        if (!mounted) return;
        setState(() => _state = _AssistantState.idle);
      case _AssistantState.speaking:
        await _voice.stopSpeaking();
        if (!mounted) return;
        setState(() => _state = _AssistantState.idle);
      case _AssistantState.error:
        if (mounted) setState(() => _state = _AssistantState.idle);
        await _voice.startListening(handsFree: true);
    }
  }

  // =========================================================================
  // CLEAR / RETRY
  // =========================================================================

  Future<void> _clearConversation() async {
    try {
      await _streamSub?.cancel();
    } catch (_) {}
    _streamSub = null;

    await _voice.stopListening();
    await _voice.stopSpeaking();

    _messages.clear();
    _lastUserMessage = null;
    _conversationId = null;
    _inputController.clear();

    if (!mounted) return;
    setState(() => _state = _AssistantState.idle);
  }

  Future<void> _retryMessage() async {
    final String? lastMessage = _lastUserMessage;
    if (lastMessage == null || lastMessage.trim().isEmpty) return;

    // Retry replaces the errored assistant turn instead of duplicating
    // the user turn in the list.
    setState(() {
      if (_messages.isNotEmpty &&
          _messages.last.status == ChatMessageStatus.error) {
        _messages.removeLast();
      }
    });

    await _sendMessage(text: lastMessage.trim(), viaVoice: false);
  }

  // =========================================================================
  // SCROLL
  // =========================================================================

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

  // =========================================================================
  // BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    final bool showChat = _messages.isNotEmpty;

    return Scaffold(
      backgroundColor: BetaColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: showChat
                    ? _buildChatView()
                    : KeyedSubtree(
                        key: const ValueKey('voice'),
                        child: _buildVoiceArea(),
                      ),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // TOP BAR
  // -------------------------------------------------------------------------

  Widget _buildTopBar() {
    final bool listening = _voice.isListening;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CircleIconButton(
            icon: Icons.menu_rounded,
            tooltip: 'Menu',
            onTap: _showMenuSheet,
          ),
          StatusPill(
            label: switch (_state) {
              _AssistantState.idle => listening ? 'Listening' : 'Live',
              _AssistantState.thinking => 'Thinking',
              _AssistantState.speaking => 'Speaking',
              _AssistantState.error => 'Error',
            },
            active: _state != _AssistantState.idle,
          ),
          CircleIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Settings',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    authService: widget.authService,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // MENU SHEET (menu icon action)
  // -------------------------------------------------------------------------

  void _showMenuSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: BetaColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: BetaColors.textSecondary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              _menuAction(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Clear conversation',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _clearConversation();
                },
              ),
              _menuAction(
                icon: Icons.logout_rounded,
                label: 'Sign out',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  widget.authService.signOut();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _menuAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: BetaColors.textSecondary),
      title: Text(label, style: BetaText.body),
      onTap: onTap,
    );
  }

  // -------------------------------------------------------------------------
  // VOICE AREA (waveform replaces the orb)
  // -------------------------------------------------------------------------

  Widget _buildVoiceArea() {
    final bool listening = _voice.isListening;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: listening
                  ? Column(
                      key: const ValueKey('waveform'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AudioWaveform(levelListenable: _audioLevel),
                        const SizedBox(height: 12),
                        Text(
                          'Listening...',
                          style: BetaText.status
                              .copyWith(color: BetaColors.textSecondary),
                        ),
                      ],
                    )
                  : Column(
                      key: const ValueKey('greeting'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Good Day', style: BetaText.greeting),
                        const SizedBox(height: 8),
                        Text('How can I help?', style: BetaText.greetingSub),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        GradientMicButton(
          icon: listening ? Icons.stop_rounded : Icons.mic_rounded,
          active: listening,
          onTap: _onMicTap,
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // CHAT VIEW
  // -------------------------------------------------------------------------

  Widget _buildChatView() {
    return Padding(
      key: const ValueKey('chat'),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          return ChatMessageBubble(
            message: _messages[index],
            onRetry: _retryMessage,
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // BOTTOM BAR
  // -------------------------------------------------------------------------

  Widget _buildBottomBar() {
    final bool listening = _voice.isListening;
    final bool canSend = _inputController.text.trim().isNotEmpty &&
        !_messageBeingSent &&
        _state != _AssistantState.thinking &&
        _state != _AssistantState.speaking;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: BetaColors.backgroundSecondary,
                borderRadius: BorderRadius.circular(27),
                border: Border.all(color: BetaColors.cardBorder),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.add_rounded,
                    color: BetaColors.textSecondary,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      onSubmitted: (_) => _sendTypedMessage(),
                      textInputAction: TextInputAction.send,
                      enabled: !_messageBeingSent,
                      style: BetaText.body,
                      decoration: const InputDecoration(
                        hintText: 'Ask anything...',
                        hintStyle: TextStyle(
                          color: BetaColors.textSecondary,
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                        isCollapsed: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: canSend ? Colors.white : Colors.white38,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: canSend ? _sendTypedMessage : null,
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.arrow_upward,
                          color: Colors.black,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          GradientMicButton(
            icon: listening ? Icons.stop_rounded : Icons.mic_rounded,
            active: listening,
            size: 54,
            onTap: _onMicTap,
          ),
        ],
      ),
    );
  }
}

enum _AssistantState { idle, thinking, speaking, error }
