
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../services/auth_service.dart';
import '../services/chat_api_service.dart';
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

  Timer? _decayTicker;

  final Random _rand = Random();

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
  // SPEECH
  // =========================================================================

  final SpeechToText _speech = SpeechToText();

  final FlutterTts _tts = FlutterTts();

  bool _speechAvailable = false;

  bool _voiceInitialized = false;

  bool _listenInProgress = false;

  bool _voiceSessionActive = false;

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

    _startAudioDecay();

    _initializeVoice();
  }

  // =========================================================================
  // DISPOSE
  // =========================================================================

  @override
  void dispose() {
    _decayTicker?.cancel();

    _streamSub?.cancel();

    _pulseController.dispose();

    _inputController.removeListener(_onTextChanged);

    _inputController.dispose();

    _scrollController.dispose();

    _speech.stop();

    _tts.stop();

    _chatApi.dispose();

    super.dispose();
  }

  // =========================================================================
  // TEXT FIELD
  // =========================================================================

  void _onTextChanged() {
    if (!mounted) return;

    setState(() {});

    _scrollToBottom();
  }

  // =========================================================================
  // AUDIO / ORB
  // =========================================================================

  void _setAudioLevel(double value) {
    if (!mounted) return;

    setState(() {
      _audioLevel = value.clamp(0.0, 1.0);
    });
  }

  void _startAudioDecay() {
    _decayTicker?.cancel();

    _decayTicker = Timer.periodic(
      const Duration(milliseconds: 70),
      (_) {
        if (!mounted) return;

        if (_audioLevel <= 0.01) {
          if (_state == _AssistantState.idle ||
              _state == _AssistantState.error) {
            _setAudioLevel(0.0);
          }

          return;
        }

        _setAudioLevel(
          (_audioLevel * 0.84).clamp(0.0, 1.0),
        );
      },
    );
  }

  void _bumpForSpeech() {
    final double bump =
        0.15 + (_rand.nextDouble() * 0.35);

    _setAudioLevel(
      (_audioLevel + bump).clamp(0.0, 1.0),
    );
  }

  void _bumpForChunk(String text) {
    final double jump =
        (text.length / 40).clamp(0.12, 0.50) +
            (_rand.nextDouble() * 0.10);

    _setAudioLevel(
      (_audioLevel + jump).clamp(0.0, 1.0),
    );
  }

  // =========================================================================
  // VOICE INITIALIZATION
  // =========================================================================

  Future<void> _initializeVoice() async {
    if (_voiceInitialized) {
      return;
    }

    try {
      debugPrint('Initializing STT...');

      _speechAvailable = await _speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
        debugLogging: true,
      );

      debugPrint(
        'STT available: $_speechAvailable',
      );

      _voiceInitialized = true;

      // ---------------------------------------------------------------------
      // TTS
      // ---------------------------------------------------------------------

      try {
        await _tts.setSpeechRate(0.5);

        await _tts.setVolume(1.0);

        await _tts.awaitSpeakCompletion(true);

        try {
          await _tts.setLanguage('en-US');
        } catch (e) {
          debugPrint(
            'TTS language warning: $e',
          );
        }

        debugPrint(
          'TTS initialized successfully',
        );
      } catch (e) {
        debugPrint(
          'TTS initialization warning: $e',
        );
      }

      if (mounted) {
        setState(() {
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint(
        'Voice initialization error: $e',
      );

      _voiceInitialized = true;

      _speechAvailable = false;

      if (!mounted) return;

      setState(() {
        _state = _AssistantState.error;

        _errorMessage =
            'Voice initialization failed.';
      });
    }
  }

  // =========================================================================
  // STT STATUS
  // =========================================================================

  void _handleSpeechStatus(String status) {
    debugPrint(
      'STT status: $status',
    );

    if (!mounted) return;

    if (status == 'listening') {
      _listenInProgress = true;

      setState(() {
        _state = _AssistantState.idle;
        _errorMessage = null;
      });

      debugPrint(
        'Microphone is actively listening.',
      );

      return;
    }

    if (status == 'notListening' ||
        status == 'done') {
      _listenInProgress = false;

      // Do not immediately clear/reset transcript state here.
      // Final recognized speech is handled by _handleSpeechResult.
      if (_state == _AssistantState.idle &&
          _inputController.text.trim().isEmpty &&
          !_voiceSessionActive) {
        setState(() {
          _audioLevel = 0.0;
        });
      }
    }
  }

  // =========================================================================
  // STT ERROR
  // =========================================================================

  void _handleSpeechError(dynamic error) {
    debugPrint(
      'STT error: $error',
    );

    _listenInProgress = false;

    final String errorText =
        error.toString().toLowerCase();

    // These are common Android speech-recognition endings when
    // nothing useful was captured.
    if (errorText.contains('error_no_match') ||
        errorText.contains('error_speech_timeout')) {
      if (!mounted) return;

      if (_inputController.text.trim().isEmpty) {
        setState(() {
          _state = _AssistantState.idle;
          _audioLevel = 0.0;
        });
      }

      return;
    }

    // Permission problems.
    if (errorText.contains('permission') ||
        errorText.contains('denied') ||
        errorText.contains('not_allowed')) {
      if (!mounted) return;

      setState(() {
        _state = _AssistantState.error;

        _audioLevel = 0.0;

        _errorMessage =
            'Microphone permission is required.';
      });

      return;
    }

    if (!mounted) return;

    setState(() {
      _state = _AssistantState.error;

      _audioLevel = 0.0;

      _errorMessage =
          'Voice recognition encountered an error.';
    });
  }

  // =========================================================================
  // START LISTENING
  // =========================================================================

  Future<void> _startListening({
    bool userInitiated = false,
  }) async {
    if (!_voiceInitialized) {
      await _initializeVoice();
    }

    if (!_speechAvailable) {
      debugPrint(
        'Speech recognition is not available.',
      );

      if (!mounted) return;

      setState(() {
        _state = _AssistantState.error;

        _errorMessage =
            'Speech recognition is unavailable.';
      });

      return;
    }

    if (_listenInProgress ||
        _speech.isListening) {
      debugPrint(
        'Ignoring duplicate listen request.',
      );

      return;
    }

    if (_messageBeingSent) {
      debugPrint(
        'Ignoring listen while message is sending.',
      );

      return;
    }

    try {
      debugPrint(
        'START LISTENING '
        '(userInitiated=$userInitiated)',
      );

      // Stop TTS before opening microphone.
      try {
        await _tts.stop();
      } catch (e) {
        debugPrint(
          'TTS stop warning: $e',
        );
      }

      // Give Android audio focus time to switch
      // from speaker back to microphone.
      await Future<void>.delayed(
        const Duration(milliseconds: 300),
      );

      if (!mounted) return;

      if (userInitiated) {
        _voiceSessionActive = true;
      }

      _errorMessage = null;

      _inputController.clear();

      _audioLevel = 0.0;

      _state = _AssistantState.idle;

      _listenInProgress = true;

      setState(() {});

      debugPrint(
        'Calling SpeechToText.listen()...',
      );

      await _speech.listen(
        onResult: _handleSpeechResult,
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(
            seconds: 30,
          ),
          pauseFor: const Duration(
            seconds: 5,
          ),
          cancelOnError: false,
          partialResults: true,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      debugPrint(
        'STT listen exception: $e',
      );

      _listenInProgress = false;

      if (!mounted) return;

      setState(() {
        _state = _AssistantState.error;

        _audioLevel = 0.0;

        _errorMessage =
            'Unable to start microphone.';
      });
    }
  }

  // =========================================================================
  // STT RESULT
  // =========================================================================

  void _handleSpeechResult(dynamic result) {
    try {
      final String text =
          result.recognizedWords
              .toString()
              .trim();

      final bool isFinal =
          result.finalResult == true;

      debugPrint(
        'STT result: "$text" '
        'final=$isFinal',
      );

      if (!mounted) return;

      if (text.isNotEmpty) {
        _inputController.value =
            TextEditingValue(
          text: text,
          selection:
              TextSelection.collapsed(
            offset: text.length,
          ),
        );

        _bumpForSpeech();

        setState(() {});
      }

      // Only send when speech recognition confirms
      // the transcript is final.
      if (isFinal && text.isNotEmpty) {
        _listenInProgress = false;

        _sendMessage(
          text: text,
          viaVoice: true,
        );
      }
    } catch (e) {
      debugPrint(
        'STT result handling error: $e',
      );
    }
  }

  // =========================================================================
  // STOP LISTENING
  // =========================================================================

  Future<void> _stopListening({
    bool endVoiceSession = false,
  }) async {
    debugPrint(
      'STOP LISTENING',
    );

    _listenInProgress = false;

    if (endVoiceSession) {
      _voiceSessionActive = false;
    }

    try {
      await _speech.stop();
    } catch (e) {
      debugPrint(
        'STT stop warning: $e',
      );
    }

    if (!mounted) return;

    setState(() {
      if (_state == _AssistantState.idle) {
        _audioLevel = 0.0;
      }
    });
  }

  // =========================================================================
  // SEND MESSAGE
  // =========================================================================

  Future<void> _sendMessage({
    String? text,
    bool viaVoice = false,
  }) async {
    final String message =
        (text ?? _inputController.text)
            .trim();

    if (message.isEmpty) {
      return;
    }

    if (_messageBeingSent) {
      debugPrint(
        'Message already being sent.',
      );

      return;
    }

    if (_state == _AssistantState.thinking ||
        _state == _AssistantState.speaking) {
      debugPrint(
        'Ignoring message while assistant is busy.',
      );

      return;
    }

    _messageBeingSent = true;

    try {
      await _stopListening(
        endVoiceSession: !viaVoice,
      );

      try {
        await _streamSub?.cancel();
      } catch (_) {}

      _streamSub = null;

      if (!mounted) return;

      _lastUserMessage = message;

      _assistantCaption = '';

      _errorMessage = null;

      setState(() {
        _state = _AssistantState.thinking;
      });

      _setAudioLevel(0.12);

      debugPrint(
        'CHAT SEND: "$message"',
      );

      _streamSub = _chatApi
          .sendMessageStream(
            message: message,
            conversationId:
                _conversationId,
          )
          .listen(
        (event) {
          if (!mounted) return;

          switch (event) {
            case ChatConversationStarted():
              _conversationId =
                  event.conversationId;

              debugPrint(
                'CHAT CONVERSATION: '
                '${event.conversationId}',
              );

            case ChatTextChunk():
              if (event.text.isEmpty) {
                return;
              }

              if (_state !=
                  _AssistantState.speaking) {
                setState(() {
                  _state =
                      _AssistantState.speaking;
                });
              }

              _assistantCaption +=
                  event.text;

              _bumpForChunk(
                event.text,
              );

              setState(() {});

              _scrollToBottom();

            case ChatStreamDone():
              debugPrint(
                'CHAT STREAM DONE',
              );

              final String response =
                  _assistantCaption.trim();

              if (response.isEmpty) {
                setState(() {
                  _state =
                      _AssistantState.idle;

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
                'CHAT STREAM ERROR: '
                '${event.detail}',
              );

              _voiceSessionActive = false;

              setState(() {
                _state =
                    _AssistantState.error;

                _errorMessage =
                    event.detail;

                _audioLevel = 0.0;
              });
          }
        },
        onError: (Object error) {
          debugPrint(
            'CHAT STREAM ERROR: $error',
          );

          if (!mounted) return;

          _voiceSessionActive = false;

          setState(() {
            _state =
                _AssistantState.error;

            _errorMessage =
                error.toString();

            _audioLevel = 0.0;
          });
        },
        onDone: () {
          debugPrint(
            'CHAT STREAM CLOSED',
          );

          _streamSub = null;
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint(
        'CHAT SEND EXCEPTION: $e',
      );

      if (!mounted) return;

      _voiceSessionActive = false;

      setState(() {
        _state =
            _AssistantState.error;

        _errorMessage =
            'Unable to contact Beta.';

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
    final String text =
        _inputController.text.trim();

    if (text.isEmpty) {
      return;
    }

    await _sendMessage(
      text: text,
      viaVoice: false,
    );
  }

  // =========================================================================
  // TTS
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

    try {
      _listenInProgress = false;

      // Stop STT before TTS.
      try {
        await _speech.stop();
      } catch (e) {
        debugPrint(
          'STT stop before TTS warning: $e',
        );
      }

      if (!mounted) return;

      setState(() {
        _state =
            _AssistantState.speaking;

        _audioLevel = 0.35;
      });

      debugPrint(
        'TTS SPEAKING...',
      );

      await _tts.speak(text);

      debugPrint(
        'TTS FINISHED',
      );

      if (!mounted) return;

      if (viaVoice &&
          _voiceSessionActive) {
        // Important Android audio-focus delay.
        await Future<void>.delayed(
          const Duration(
            milliseconds: 500,
          ),
        );

        if (!mounted) return;

        debugPrint(
          'Returning to listening mode...',
        );

        await _startListening(
          userInitiated: false,
        );
      } else {
        _voiceSessionActive = false;

        setState(() {
          _state =
              _AssistantState.idle;

          _audioLevel = 0.0;
        });
      }
    } catch (e) {
      debugPrint(
        'TTS error: $e',
      );

      _voiceSessionActive = false;

      if (!mounted) return;

      setState(() {
        _state =
            _AssistantState.error;

        _audioLevel = 0.0;

        _errorMessage =
            'Beta could not speak the response.';
      });
    }
  }

  // =========================================================================
  // ORB TAP
  // =========================================================================

  Future<void> _onOrbTap() async {
    switch (_state) {
      case _AssistantState.idle:
        await _startListening(
          userInitiated: true,
        );
        break;

      case _AssistantState.thinking:
        debugPrint(
          'Stopping current request...',
        );

        try {
          await _streamSub?.cancel();
        } catch (_) {}

        _streamSub = null;

        _voiceSessionActive = false;

        if (!mounted) return;

        setState(() {
          _state =
              _AssistantState.idle;

          _audioLevel = 0.0;
        });
        break;

      case _AssistantState.speaking:
        debugPrint(
          'Stopping TTS...',
        );

        try {
          await _tts.stop();
        } catch (e) {
          debugPrint(
            'TTS stop error: $e',
          );
        }

        _voiceSessionActive = false;

        if (!mounted) return;

        setState(() {
          _state =
              _AssistantState.idle;

          _audioLevel = 0.0;
        });
        break;

      case _AssistantState.error:
        _errorMessage = null;

        if (mounted) {
          setState(() {
            _state =
                _AssistantState.idle;
          });
        }

        await _startListening(
          userInitiated: true,
        );
        break;
    }
  }

  // =========================================================================
  // CLEAR CONVERSATION
  // =========================================================================

  Future<void> _clearConversation() async {
    debugPrint(
      'CLEARING CONVERSATION',
    );

    try {
      await _streamSub?.cancel();
    } catch (_) {}

    _streamSub = null;

    try {
      await _speech.stop();
    } catch (_) {}

    try {
      await _tts.stop();
    } catch (_) {}

    _voiceSessionActive = false;

    _listenInProgress = false;

    _assistantCaption = '';

    _lastUserMessage = null;

    _conversationId = null;

    _errorMessage = null;

    _inputController.clear();

    if (!mounted) return;

    setState(() {
      _state =
          _AssistantState.idle;

      _audioLevel = 0.0;
    });
  }

  // =========================================================================
  // RETRY
  // =========================================================================

  Future<void> _retryMessage() async {
    final String? lastMessage =
        _lastUserMessage;

    if (lastMessage == null ||
        lastMessage.trim().isEmpty) {
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
    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (!_scrollController
          .hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController
            .position
            .maxScrollExtent,
        duration:
            const Duration(
          milliseconds: 220,
        ),
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
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation:
                          _pulseController,
                      builder:
                          (context, child) {
                        final double breathe =
                            0.05 *
                                sin(
                                  _pulseController
                                          .value *
                                      2 *
                                      pi,
                                );

                        final double scale =
                            1.0 +
                                breathe +
                                (_audioLevel *
                                    0.12);

                        return Transform.scale(
                          scale: scale,
                          child: child,
                        );
                      },
                      child: GestureDetector(
                        onTap: _onOrbTap,
                        child: VoiceOrb(
                          audioLevel:
                              _audioLevel,
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 28,
                    ),

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
    if (_state ==
            _AssistantState.error &&
        _errorMessage != null) {
      return Padding(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 32,
        ),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Text(
              _errorMessage!,
              textAlign:
                  TextAlign.center,
              style: const TextStyle(
                color:
                    Colors.redAccent,
                fontSize: 13,
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            TextButton(
              onPressed:
                  _retryMessage,
              child: const Text(
                'Retry',
              ),
            ),
          ],
        ),
      );
    }

    if (_listenInProgress ||
        _speech.isListening) {
      return const Text(
        'Listening...',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 14,
        ),
      );
    }

    if (_state ==
        _AssistantState.thinking) {
      return const Text(
        'Thinking...',
        style: TextStyle(
          color: Colors.white38,
          fontSize: 14,
        ),
      );
    }

    if (_state ==
            _AssistantState.speaking &&
        _assistantCaption.isNotEmpty) {
      return Padding(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 32,
        ),
        child: Text(
          _assistantCaption,
          textAlign:
              TextAlign.center,
          maxLines: 6,
          overflow:
              TextOverflow.ellipsis,
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
        padding:
            const EdgeInsets.symmetric(
          horizontal: 32,
        ),
        child: Text(
          _assistantCaption,
          textAlign:
              TextAlign.center,
          maxLines: 6,
          overflow:
              TextOverflow.ellipsis,
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
        padding:
            const EdgeInsets.symmetric(
          horizontal: 32,
        ),
        child: Text(
          _lastUserMessage!,
          textAlign:
              TextAlign.center,
          maxLines: 3,
          overflow:
              TextOverflow.ellipsis,
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
      padding:
          const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
        children: [
          // Long press clears conversation.
          GestureDetector(
            onLongPress:
                _clearConversation,
            child: _circleIconButton(
              icon: Icons.logout,
              onTap: () {
                _voiceSessionActive =
                    false;

                widget.authService
                    .signOut();
              },
            ),
          ),

          _livePill(),

          _circleIconButton(
            icon: Icons.tune,
            onTap: () {
              Navigator.of(context)
                  .push(
                MaterialPageRoute(
                  builder: (_) =>
                      SettingsScreen(
                    authService:
                        widget.authService,
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
    final String label =
        switch (_state) {
      _AssistantState.idle =>
        'Live',

      _AssistantState.thinking =>
        'Thinking',

      _AssistantState.speaking =>
        'Speaking',

      _AssistantState.error =>
        'Error',
    };

    return Container(
      height: 44,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 22,
      ),
      decoration: BoxDecoration(
        color:
            const Color(0xFF2A2A2A),
        borderRadius:
            BorderRadius.circular(
          22,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight:
              FontWeight.w600,
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
      color:
          const Color(0xFF2A2A2A),
      shape:
          const CircleBorder(),
      child: InkWell(
        customBorder:
            const CircleBorder(),
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
    final bool canSend =
        _inputController.text
                .trim()
                .isNotEmpty &&
            !_messageBeingSent &&
            _state !=
                _AssistantState.thinking &&
            _state !=
                _AssistantState.speaking;

    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16,
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 52,
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 16,
              ),
              decoration:
                  BoxDecoration(
                color:
                    const Color(0xFF2A2A2A),
                borderRadius:
                    BorderRadius.circular(
                  26,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.add,
                    color:
                        Colors.white70,
                  ),

                  const SizedBox(
                    width: 10,
                  ),

                  Expanded(
                    child: TextField(
                      controller:
                          _inputController,
                      onSubmitted: (_) =>
                          _sendTypedMessage(),
                      textInputAction:
                          TextInputAction
                              .send,
                      enabled:
                          !_messageBeingSent,
                      style:
                          const TextStyle(
                        color:
                            Colors.white,
                        fontSize: 16,
                      ),
                      decoration:
                          const InputDecoration(
                        hintText:
                            'Ask Beta',
                        hintStyle:
                            TextStyle(
                          color:
                              Colors.white54,
                          fontSize: 16,
                        ),
                        border:
                            InputBorder.none,
                        isCollapsed:
                            true,
                      ),
                    ),
                  ),

                  InkWell(
                    onTap:
                        _messageBeingSent
                            ? null
                            : () async {
                                if (_state ==
                                    _AssistantState
                                        .speaking) {
                                  try {
                                    await _tts
                                        .stop();
                                  } catch (_) {}

                                  _voiceSessionActive =
                                      false;

                                  if (mounted) {
                                    setState(() {
                                      _state =
                                          _AssistantState
                                              .idle;

                                      _audioLevel =
                                          0.0;
                                    });
                                  }

                                  return;
                                }

                                if (_state ==
                                    _AssistantState
                                        .idle) {
                                  await _startListening(
                                    userInitiated:
                                        true,
                                  );
                                } else if (_state ==
                                    _AssistantState
                                        .error) {
                                  await _startListening(
                                    userInitiated:
                                        true,
                                  );
                                }
                              },
                    child: Icon(
                      _listenInProgress ||
                              _speech
                                  .isListening
                          ? Icons
                              .mic_rounded
                          : Icons
                              .mic_none_rounded,
                      color:
                          _listenInProgress ||
                                  _speech
                                      .isListening
                              ? Colors.white
                              : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(
            width: 12,
          ),

          Material(
            color: canSend
                ? Colors.white
                : Colors.white38,
            shape:
                const CircleBorder(),
            child: InkWell(
              customBorder:
                  const CircleBorder(),
              onTap:
                  canSend
                      ? _sendTypedMessage
                      : null,
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
    );
  }
}

