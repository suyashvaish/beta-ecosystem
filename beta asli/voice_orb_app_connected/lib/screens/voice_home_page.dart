import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/chat_api_service.dart';
import '../services/voice_controller.dart';
import '../widgets/voice_orb.dart';
import 'settings_screen.dart';

enum _AssistantState {
  idle,
  thinking,
  speaking,
  error,
}

class VoiceHomePage extends StatefulWidget {
  const VoiceHomePage({
    super.key,
    required this.authService,
  });

  final AuthService authService;

  @override
  State<VoiceHomePage> createState() => _VoiceHomePageState();
}

class _VoiceHomePageState extends State<VoiceHomePage>
    with SingleTickerProviderStateMixin {
  // =========================================================================
  // ORB / AUDIO
  // =========================================================================

  double _audioLevel = 0.0;

  _AssistantState _state = _AssistantState.idle;

  late final AnimationController _pulseController;

  // =========================================================================
  // CHAT
  // =========================================================================

  late final ChatApiService _chatApi;

  String? _conversationId;

  StreamSubscription<ChatStreamEvent>? _streamSub;

  String _assistantCaption = '';

  String? _lastUserMessage;

  String? _errorMessage;

  bool _messageBeingSent = false;

  // =========================================================================
  // VOICE (fixed pipeline)
  // =========================================================================
  // All STT/TTS handling lives in VoiceController. This screen only maps
  // controller callbacks to UI state - the old buggy handlers
  // (_handleSpeechStatus/_handleSpeechError/_startListening/_speakAssistantResponse
  // and the fake random _bumpForSpeech/_bumpForChunk levels) are gone.
  // See VOICE_FIXES.md for the root-cause analysis of what they got wrong.

  late final VoiceController _voice;

  // =========================================================================
  // TEXT INPUT
  // =========================================================================

  final TextEditingController _inputController =
      TextEditingController();

  final ScrollController _scrollController =
      ScrollController();

  // =========================================================================
  // INIT
  // =========================================================================

  @override
  void initState() {
    super.initState();

    _chatApi = ChatApiService(
      authService: widget.authService,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _inputController.addListener(_onTextChanged);

    _voice = VoiceController(
      onStateChanged: _onVoiceStateChanged,
      onLevelChanged: _setAudioLevel,
      onPartialTranscript: _onPartialTranscript,
      onFinalTranscript: _onFinalTranscript,
      onError: _onVoiceError,
    );
  }

  // =========================================================================
  // DISPOSE
  // =========================================================================

  @override
  void dispose() {
    _streamSub?.cancel();

    _pulseController.dispose();

    _inputController.removeListener(_onTextChanged);

    _inputController.dispose();

    _scrollController.dispose();

    // Fire-and-forget: the controller stops STT/TTS and cleans up; there
    // is no UI left to await the result.
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
          // Listening keeps the idle orb but shows the 'Listening...'
          // caption via _voice.isListening below.
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
      selection: TextSelection.collapsed(
        offset: transcript.length,
      ),
    );

    setState(() {});
  }

  void _onFinalTranscript(String transcript) {
    // The controller has already moved to processing state; send the
    // recognized text as a voice turn.
    _sendMessage(
      text: transcript,
      viaVoice: true,
    );
  }

  void _onVoiceError(String message) {
    if (!mounted) return;

    setState(() {
      _errorMessage = message;
    });
  }

  // =========================================================================
  // AUDIO / ORB
  // =========================================================================

  void _setAudioLevel(double value) {
    if (!mounted) return;

    setState(() {
      // Real microphone dB readings from VoiceController - no decay
      // ticker needed; the controller reports the actual level.
      _audioLevel = value.clamp(0.0, 1.0);
    });
  }

  // =========================================================================
  // SEND MESSAGE
  // =========================================================================

  Future<void> _sendMessage({
    String? text,
    bool viaVoice = false,
  }) async {
    final String message = (text ?? _inputController.text).trim();

    if (message.isEmpty) {
      return;
    }

    if (_messageBeingSent) {
      debugPrint('Message already being sent.');

      return;
    }

    if (_state == _AssistantState.thinking ||
        _state == _AssistantState.speaking) {
      debugPrint('Ignoring message while assistant is busy.');

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

      _assistantCaption = '';

      _errorMessage = null;

      if (!viaVoice) {
        _inputController.clear();
      }

      setState(() {
        _state = _AssistantState.thinking;
      });

      _setAudioLevel(0.12);

      debugPrint('CHAT SEND: "$message"');

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

              debugPrint(
                'CHAT CONVERSATION: ${event.conversationId}',
              );

            case ChatTextChunk():
              if (event.text.isEmpty) {
                return;
              }

              if (_state != _AssistantState.speaking) {
                setState(() {
                  _state = _AssistantState.speaking;
                });
              }

              _assistantCaption += event.text;

              setState(() {});

              _scrollToBottom();

            case ChatStreamDone():
              debugPrint('CHAT STREAM DONE');

              final String response = _assistantCaption.trim();

              if (response.isEmpty) {
                setState(() {
                  _state = _AssistantState.idle;
                  _audioLevel = 0.0;
                });

                return;
              }

              unawaited(
                _speakAssistantResponse(
                  response,
                  viaVoice: viaVoice,
                ),
              );

            case ChatStreamError():
              debugPrint(
                'CHAT STREAM ERROR: ${event.detail}',
              );

              setState(() {
                _state = _AssistantState.error;
                _errorMessage = event.detail;
                _audioLevel = 0.0;
              });
          }
        },
        onError: (Object error) {
          debugPrint('CHAT STREAM ERROR: $error');

          if (!mounted) return;

          setState(() {
            _state = _AssistantState.error;
            _errorMessage = 'Unable to contact Beta.';
            _audioLevel = 0.0;
          });
        },
        onDone: () {
          debugPrint('CHAT STREAM CLOSED');
          _streamSub = null;
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('CHAT SEND EXCEPTION: $e');

      if (!mounted) return;

      setState(() {
        _state = _AssistantState.error;
        _errorMessage = 'Unable to contact Beta.';
        _audioLevel = 0.0;
      });
    } finally {
      _messageBeingSent = false;
    }
  }

  // =========================================================================
  // TEXT SEND
  // =========================================================================

  Future<void> _sendTypedMessage() async {
    final String text = _inputController.text.trim();

    if (text.isEmpty) {
      return;
    }

    await _sendMessage(
      text: text,
      viaVoice: false,
    );
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

      setState(() {
        _state = _AssistantState.idle;
        _audioLevel = 0.0;
      });

      return;
    }

    // The controller reports real errors (missing TTS engine, silent
    // speak) via onError; it resolves false when playback never started.
    final bool spoke = await _voice.speak(text);

    if (!mounted) return;

    if (!spoke) {
      setState(() {
        _state = _AssistantState.error;
        _audioLevel = 0.0;
      });

      return;
    }

    if (viaVoice) {
      // Re-arm the hands-free loop: real audio focus handover delay is
      // handled inside the controller before it opens the microphone.
      await _voice.startListening(handsFree: true);
    } else {
      setState(() {
        _state = _AssistantState.idle;
        _audioLevel = 0.0;
      });
    }
  }

  // =========================================================================
  // ORB TAP
  // =========================================================================

  Future<void> _onOrbTap() async {
    switch (_state) {
      case _AssistantState.idle:
        await _voice.startListening(handsFree: true);
        break;

      case _AssistantState.thinking:
        debugPrint('Stopping current request...');

        try {
          await _streamSub?.cancel();
        } catch (_) {}

        _streamSub = null;

        await _voice.stopListening();

        if (!mounted) return;

        setState(() {
          _state = _AssistantState.idle;
          _audioLevel = 0.0;
        });
        break;

      case _AssistantState.speaking:
        debugPrint('Stopping TTS...');

        await _voice.stopSpeaking();

        if (!mounted) return;

        setState(() {
          _state = _AssistantState.idle;
          _audioLevel = 0.0;
        });
        break;

      case _AssistantState.error:
        _errorMessage = null;

        if (mounted) {
          setState(() {
            _state = _AssistantState.idle;
          });
        }

        await _voice.startListening(handsFree: true);
        break;
    }
  }

  // =========================================================================
  // CLEAR CONVERSATION
  // =========================================================================

  Future<void> _clearConversation() async {
    debugPrint('CLEARING CONVERSATION');

    try {
      await _streamSub?.cancel();
    } catch (_) {}

    _streamSub = null;

    await _voice.stopListening();

    await _voice.stopSpeaking();

    _assistantCaption = '';

    _lastUserMessage = null;

    _conversationId = null;

    _errorMessage = null;

    _inputController.clear();

    if (!mounted) return;

    setState(() {
      _state = _AssistantState.idle;
      _audioLevel = 0.0;
    });
  }

  // =========================================================================
  // RETRY
  // =========================================================================

  Future<void> _retryMessage() async {
    final String? lastMessage = _lastUserMessage;

    if (lastMessage == null || lastMessage.trim().isEmpty) {
      return;
    }

    await _sendMessage(
      text: lastMessage.trim(),
      viaVoice: false,
    );
  }

  // =========================================================================
  // SCROLL
  // =========================================================================

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

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
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),

            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final double breathe = 0.05 *
                            sin(_pulseController.value * 2 * pi);

                        final double scale =
                            1.0 + breathe + (_audioLevel * 0.12);

                        return Transform.scale(
                          scale: scale,
                          child: child,
                        );
                      },
                      child: GestureDetector(
                        onTap: _onOrbTap,
                        child: VoiceOrb(
                          audioLevel: _audioLevel,
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    _buildCaption(),
                  ],
                ),
              ),
            ),

            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // CAPTION
  // =========================================================================

  Widget _buildCaption() {
    if (_state == _AssistantState.error && _errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _retryMessage,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_voice.isListening) {
      return const Text(
        'Listening...',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 14,
        ),
      );
    }

    if (_state == _AssistantState.thinking) {
      return const Text(
        'Thinking...',
        style: TextStyle(
          color: Colors.white38,
          fontSize: 14,
        ),
      );
    }

    if (_state == _AssistantState.speaking &&
        _assistantCaption.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          _assistantCaption,
          textAlign: TextAlign.center,
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 15,
            height: 1.4,
          ),
        ),
      );
    }

    if (_assistantCaption.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          _assistantCaption,
          textAlign: TextAlign.center,
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 15,
            height: 1.4,
          ),
        ),
      );
    }

    if (_lastUserMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          _lastUserMessage!,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 14,
          ),
        ),
      );
    }

    return const Text(
      'Tap Beta to talk',
      style: TextStyle(
        color: Colors.white38,
        fontSize: 14,
      ),
    );
  }

  // =========================================================================
  // TOP BAR
  // =========================================================================

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Long press clears conversation.
          GestureDetector(
            onLongPress: _clearConversation,
            child: _circleIconButton(
              icon: Icons.logout,
              onTap: () {
                widget.authService.signOut();
              },
            ),
          ),

          _livePill(),

          _circleIconButton(
            icon: Icons.tune,
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

  // =========================================================================
  // LIVE PILL
  // =========================================================================

  Widget _livePill() {
    final String label = switch (_state) {
      _AssistantState.idle => 'Live',
      _AssistantState.thinking => 'Thinking',
      _AssistantState.speaking => 'Speaking',
      _AssistantState.error => 'Error',
    };

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(22),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // =========================================================================
  // CIRCLE BUTTON
  // =========================================================================

  Widget _circleIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF2A2A2A),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // BOTTOM BAR
  // =========================================================================

  Widget _buildBottomBar() {
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
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: _voice.isListening
                        ? () => _voice.stopListening()
                        : () => _voice.startListening(handsFree: true),
                    child: Icon(
                      _voice.isListening
                          ? Icons.mic_rounded
                          : Icons.mic_none_rounded,
                      color: _voice.isListening
                          ? Colors.white
                          : Colors.white70,
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      onSubmitted: (_) => _sendTypedMessage(),
                      textInputAction: TextInputAction.send,
                      enabled: !_messageBeingSent,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Ask Beta',
                        hintStyle: TextStyle(
                          color: Colors.white54,
                          fontSize: 16,
                        ),
                        border: InputBorder.none,
                        isCollapsed: true,
                      ),
                    ),
                  ),

                  Material(
                    color: canSend ? Colors.white : Colors.white38,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: canSend ? _sendTypedMessage : null,
                      child: const SizedBox(
                        width: 52,
                        height: 52,
                        child: Icon(
                          Icons.arrow_upward,
                          color: Colors.black,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}