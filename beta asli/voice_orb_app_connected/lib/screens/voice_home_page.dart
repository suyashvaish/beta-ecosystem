import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/chat_message.dart';
import '../services/auth_service.dart';
import '../services/chat_api_service.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/voice_orb.dart';
import 'settings_screen.dart';

/// The single source of truth for what Beta is doing right now. Replaces
/// the old pairing of a 4-value enum plus a separate `_isListening` bool
/// that could drift out of sync with each other - see spec section 3.
enum BetaVoiceState { idle, listening, processing, speaking, error }

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
  // ------------------------------------------------------------
  // ORB / VOICE STATE
  // ------------------------------------------------------------

  double _audioLevel = 0.0;
  BetaVoiceState _voiceState = BetaVoiceState.idle;
  String? _errorMessage;

  /// True from the moment the user taps the orb/mic to start talking
  /// until they leave voice mode (manual stop, switching to typing, a
  /// "didn't catch that" timeout, or a real error). While true, Beta
  /// automatically listens again after it finishes speaking - that's
  /// the whole hands-free loop. Any single failed listen attempt turns
  /// this off rather than retrying, so it can never spin (spec section 4:
  /// "do not continuously restart... return to IDLE").
  bool _voiceSessionActive = false;

  Timer? _decayTicker;
  final Random _rand = Random();

  late final AnimationController _pulseController;

  // ------------------------------------------------------------
  // CHAT
  // ------------------------------------------------------------

  late final ChatApiService _chatApi;

  final List<ChatMessage> _messages = [];
  int _messageCounter = 0;

  String? _conversationId;
  StreamSubscription? _streamSub;

  // ------------------------------------------------------------
  // SPEECH
  // ------------------------------------------------------------

  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _speechAvailable = false;

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool get _hasConversation => _messages.isNotEmpty;

  OrbVisualState get _orbState => switch (_voiceState) {
        BetaVoiceState.idle => OrbVisualState.idle,
        BetaVoiceState.listening => OrbVisualState.listening,
        BetaVoiceState.processing => OrbVisualState.processing,
        BetaVoiceState.speaking => OrbVisualState.speaking,
        BetaVoiceState.error => OrbVisualState.error,
      };

  // ------------------------------------------------------------
  // INIT
  // ------------------------------------------------------------

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

    _initializeVoice();
  }

  // ------------------------------------------------------------
  // ERROR MESSAGES
  // ------------------------------------------------------------

  /// Logs the real error for debugging and returns a short, friendly
  /// message that's safe to show in the UI. Raw exception/technical text
  /// should never reach the screen directly (spec section 31).
  String _friendlyError(Object error, [String context = 'Error']) {
    debugPrint('$context: $error');
    return "Beta couldn't do that right now. Please check your connection "
        'and try again.';
  }

  // ------------------------------------------------------------
  // VOICE INITIALIZATION
  // ------------------------------------------------------------

  Future<void> _initializeVoice() async {
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          debugPrint('STT status: $status');

          if (!mounted) return;

          if ((status == 'notListening' || status == 'done') &&
              _voiceState == BetaVoiceState.listening) {
            setState(() => _voiceState = BetaVoiceState.idle);
          }
        },
        onError: (error) {
          debugPrint(
            'STT error: ${error.errorMsg} (permanent: ${error.permanent})',
          );

          if (!mounted) return;

          // "No match" and "timeout" just mean the user didn't say
          // anything recognizable in time - that's normal, not a
          // failure. Recover quietly instead of a scary error state,
          // and end any hands-free session rather than retrying.
          final benign = error.errorMsg == 'error_no_match' ||
              error.errorMsg == 'error_speech_timeout';

          setState(() {
            _voiceSessionActive = false;

            if (benign) {
              _voiceState = BetaVoiceState.idle;
            } else if (error.errorMsg == 'error_insufficient_permissions') {
              _voiceState = BetaVoiceState.error;
              _errorMessage =
                  'Microphone access is required for voice conversations. '
                  'Please enable microphone access in Settings.';
            } else {
              _voiceState = BetaVoiceState.error;
              _errorMessage = 'Voice input had a problem. Please try again.';
            }
          });
        },
      );

      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);

      debugPrint('STT available: $_speechAvailable');
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _speechAvailable = false;
        _voiceState = BetaVoiceState.error;
        _errorMessage = _friendlyError(e, 'Voice initialization error');
      });
    }
  }

  // ------------------------------------------------------------
  // START / STOP LISTENING
  // ------------------------------------------------------------

  Future<void> _startListening({required bool userInitiated}) async {
    if (!_speechAvailable) {
      if (mounted) {
        setState(() {
          _voiceSessionActive = false;
          _errorMessage =
              'Speech recognition is not available on this device.';
          _voiceState = BetaVoiceState.error;
        });
      }
      return;
    }

    if (_voiceState == BetaVoiceState.listening) return;
    if (!mounted) return;

    try {
      await _tts.stop();
    } catch (_) {
      // Nothing to stop - fine.
    }

    if (userInitiated) {
      _voiceSessionActive = true;
    }

    setState(() {
      _voiceState = BetaVoiceState.listening;
      _errorMessage = null;
      _audioLevel = 0.4;
      _inputController.clear();
    });

    try {
      await _speech.listen(
        onResult: (result) {
          final text = result.recognizedWords.trim();

          debugPrint('STT result: $text');

          if (!mounted) return;

          setState(() {
            _inputController.text = text;
            _inputController.selection = TextSelection.collapsed(
              offset: _inputController.text.length,
            );
          });

          if (result.finalResult && text.isNotEmpty) {
            _sendMessage(viaVoice: true);
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        listenOptions: SpeechListenOptions(
          cancelOnError: true,
          partialResults: true,
          listenMode: ListenMode.confirmation,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _voiceSessionActive = false;
        _voiceState = BetaVoiceState.error;
        _errorMessage = _friendlyError(e, 'STT start error');
      });
    }
  }

  Future<void> _stopListening({bool endSession = false}) async {
    if (endSession) _voiceSessionActive = false;

    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('STT stop error: $e');
    }

    if (!mounted) return;

    if (_voiceState == BetaVoiceState.listening) {
      setState(() {
        _voiceState = BetaVoiceState.idle;
        _audioLevel = 0.0;
      });
    }
  }

  // ------------------------------------------------------------
  // AUDIO LEVEL (drives the orb's glow/gradient intensity)
  // ------------------------------------------------------------

  void _setAudioLevel(double value) {
    if (!mounted) return;

    setState(() {
      _audioLevel = value.clamp(0.0, 1.0);
    });
  }

  void _startDecayTicker({
    required double baseline,
  }) {
    _decayTicker?.cancel();

    _decayTicker = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) {
        final next = _audioLevel - 0.03;

        _setAudioLevel(
          next < baseline ? baseline : next,
        );
      },
    );
  }

  void _stopDecayTicker() {
    _decayTicker?.cancel();
    _decayTicker = null;

    _setAudioLevel(0.0);
  }

  void _bumpForChunk(String text) {
    final jump = (text.length / 40).clamp(0.15, 0.55) +
        (_rand.nextDouble() * 0.1);

    _setAudioLevel(
      (_audioLevel + jump).clamp(0.0, 1.0),
    );
  }

  // ------------------------------------------------------------
  // SEND MESSAGE
  // ------------------------------------------------------------

  Future<void> _sendMessage({required bool viaVoice}) async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    // Don't let a double-tap or an overlapping voice result start a
    // second turn while one is already in flight.
    if (_voiceState == BetaVoiceState.processing ||
        _voiceState == BetaVoiceState.speaking) {
      return;
    }

    if (!viaVoice) {
      // Typing a message always exits the hands-free voice loop.
      _voiceSessionActive = false;
    }

    await _stopListening();

    _inputController.clear();

    await _streamSub?.cancel();
    _streamSub = null;

    final userMessage = ChatMessage(
      id: 'u${_messageCounter++}',
      role: ChatRole.user,
      text: text,
    );
    final assistantMessage = ChatMessage(
      id: 'a${_messageCounter++}',
      role: ChatRole.assistant,
      status: ChatMessageStatus.streaming,
    );

    if (!mounted) return;

    setState(() {
      _messages.add(userMessage);
      _messages.add(assistantMessage);
      _errorMessage = null;
      _voiceState = BetaVoiceState.processing;
    });
    _scrollToBottom();

    _startDecayTicker(baseline: 0.12);

    try {
      _streamSub = _chatApi
          .sendMessageStream(
        message: text,
        conversationId: _conversationId,
      )
          .listen(
        (event) {
          if (!mounted) return;

          switch (event) {
            case ChatConversationStarted():
              _conversationId = event.conversationId;
              break;

            case ChatTextChunk():
              if (event.text.isEmpty) break;

              if (_voiceState != BetaVoiceState.speaking) {
                setState(() => _voiceState = BetaVoiceState.speaking);
              }

              setState(() {
                assistantMessage.text += event.text;
                assistantMessage.status = ChatMessageStatus.streaming;
              });

              _bumpForChunk(event.text);
              _scrollToBottom();
              break;

            case ChatStreamDone():
              debugPrint('CHAT STREAM DONE');

              _stopDecayTicker();

              setState(() {
                assistantMessage.status = ChatMessageStatus.complete;
              });

              debugPrint(
                'COMPLETE AI RESPONSE: "${assistantMessage.text}"',
              );

              // IMPORTANT: not awaited - this callback isn't async.
              _speakAssistantResponse(assistantMessage.text);
              break;

            case ChatStreamError():
              _stopDecayTicker();

              setState(() {
                _voiceState = BetaVoiceState.error;
                assistantMessage.status = ChatMessageStatus.error;
                assistantMessage.text =
                    _friendlyError(event.detail, 'Chat stream error');
              });
              break;
          }
        },
        onError: (error) {
          _stopDecayTicker();

          if (!mounted) return;

          setState(() {
            _voiceState = BetaVoiceState.error;
            assistantMessage.status = ChatMessageStatus.error;
            assistantMessage.text =
                _friendlyError(error, 'Chat stream error');
          });
        },
        onDone: () {
          debugPrint('CHAT STREAM CLOSED');
          // Do not force the state to idle here - TTS controls
          // speaking -> idle (or -> listening again, hands-free).
        },
      );
    } catch (e) {
      _stopDecayTicker();

      if (!mounted) return;

      setState(() {
        _voiceState = BetaVoiceState.error;
        assistantMessage.status = ChatMessageStatus.error;
        assistantMessage.text = _friendlyError(e, 'Send message error');
      });
    }
  }

  /// Removes a failed exchange and resends the same user text.
  void _retryMessage(ChatMessage failedAssistantMessage) {
    final index = _messages.indexOf(failedAssistantMessage);
    if (index <= 0) return;

    final userMessage = _messages[index - 1];
    if (userMessage.role != ChatRole.user) return;

    final textToRetry = userMessage.text;

    setState(() {
      _messages.removeRange(index - 1, index + 1);
    });

    _inputController.text = textToRetry;
    _sendMessage(viaVoice: false);
  }

  void _clearConversation() {
    _streamSub?.cancel();
    _streamSub = null;
    _stopDecayTicker();
    _voiceSessionActive = false;
    _tts.stop();
    _speech.stop();

    setState(() {
      _messages.clear();
      _conversationId = null;
      _errorMessage = null;
      _voiceState = BetaVoiceState.idle;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ------------------------------------------------------------
  // SPEAK
  // ------------------------------------------------------------

  Future<void> _speakAssistantResponse(String text) async {
    final trimmed = text.trim();

    if (trimmed.isEmpty) {
      if (!mounted) return;
      setState(() => _voiceState = BetaVoiceState.idle);
      return;
    }

    try {
      if (!mounted) return;
      setState(() => _voiceState = BetaVoiceState.speaking);

      await _tts.speak(trimmed);

      if (!mounted) return;

      // Hands-free loop: only continue if the user started this turn by
      // voice and hasn't left voice mode since. A single failed listen
      // attempt (see onError above) turns this off, so it can't spin.
      if (_voiceSessionActive) {
        await _startListening(userInitiated: false);
      } else {
        setState(() => _voiceState = BetaVoiceState.idle);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _voiceSessionActive = false;
        _voiceState = BetaVoiceState.error;
        _errorMessage = _friendlyError(e, 'TTS error');
      });
    }
  }

  // ------------------------------------------------------------
  // ORB TAP
  // ------------------------------------------------------------

  Future<void> _onOrbTap() async {
    if (_voiceState == BetaVoiceState.idle ||
        _voiceState == BetaVoiceState.error) {
      setState(() => _errorMessage = null);
      await _startListening(userInitiated: true);
      return;
    }

    if (_voiceState == BetaVoiceState.listening) {
      await _stopListening(endSession: true);
      return;
    }

    if (_voiceState == BetaVoiceState.speaking) {
      await _tts.stop();
      if (!mounted) return;
      setState(() {
        _voiceSessionActive = false;
        _voiceState = BetaVoiceState.idle;
      });
      return;
    }

    // Only BetaVoiceState.processing remains here - cancel the in-flight
    // request rather than leaving it to finish silently in the background.
    await _streamSub?.cancel();
    _streamSub = null;
    _stopDecayTicker();
    if (!mounted) return;
    setState(() {
      _voiceSessionActive = false;
      _voiceState = BetaVoiceState.idle;
    });
  }

  String _statusLine() {
    switch (_voiceState) {
      case BetaVoiceState.listening:
        return 'Listening…';
      case BetaVoiceState.processing:
        return 'Thinking…';
      case BetaVoiceState.error:
        return _errorMessage ?? 'Something went wrong.';
      case BetaVoiceState.idle:
      case BetaVoiceState.speaking:
        return '';
    }
  }

  // ------------------------------------------------------------
  // TOP BAR
  // ------------------------------------------------------------

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _circleIconButton(
            icon: Icons.logout,
            onTap: () async {
              try {
                await widget.authService.signOut();
              } catch (e) {
                debugPrint('Sign out error: $e');
              }
            },
          ),

          _statusPill(),

          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasConversation) ...[
                _circleIconButton(
                  icon: Icons.add_comment_outlined,
                  onTap: _clearConversation,
                ),
                const SizedBox(width: 10),
              ],
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
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // STATUS PILL (carries a small live orb badge once chatting)
  // ------------------------------------------------------------

  Widget _statusPill() {
    final label = switch (_voiceState) {
      BetaVoiceState.idle => _hasConversation ? 'Beta' : 'Live',
      BetaVoiceState.listening => 'Listening',
      BetaVoiceState.processing => 'Thinking',
      BetaVoiceState.speaking => 'Speaking',
      BetaVoiceState.error => 'Error',
    };

    return Container(
      height: 44,
      padding: EdgeInsets.symmetric(
        horizontal: _hasConversation ? 14 : 22,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(22),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_hasConversation) ...[
            VoiceOrb(
              audioLevel: _audioLevel,
              state: _orbState,
              size: 22,
            ),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // CIRCLE BUTTON
  // ------------------------------------------------------------

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
            color: Colors.white70,
            size: 20,
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // ORB HERO (shown until the first message exists)
  // ------------------------------------------------------------

  Widget _buildOrbHero() {
    return Center(
      key: const ValueKey('orb-hero'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final breathe = 0.05 * sin(_pulseController.value * 2 * pi);
              final processingBoost =
                  _voiceState == BetaVoiceState.processing ? 1.6 : 1.0;
              final scale =
                  1.0 + (breathe * processingBoost) + (_audioLevel * 0.12);

              return Transform.scale(scale: scale, child: child);
            },
            child: GestureDetector(
              onTap: _onOrbTap,
              child: VoiceOrb(
                audioLevel: _audioLevel,
                state: _orbState,
                size: 240,
              ),
            ),
          ),

          const SizedBox(height: 28),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _statusLine().isNotEmpty
                  ? _statusLine()
                  : 'Tap to talk to Beta',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _voiceState == BetaVoiceState.error
                    ? Colors.redAccent
                    : Colors.white54,
                fontSize: _voiceState == BetaVoiceState.error ? 13 : 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // CHAT LIST (once a conversation exists)
  // ------------------------------------------------------------

  Widget _buildChatList() {
    return Column(
      key: const ValueKey('chat-list'),
      children: [
        if (_voiceState == BetaVoiceState.listening ||
            _voiceState == BetaVoiceState.error)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: Text(
              _statusLine(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _voiceState == BetaVoiceState.error
                    ? Colors.redAccent
                    : Colors.white54,
                fontSize: 13,
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              return ChatMessageBubble(
                message: message,
                onRetry: message.status == ChatMessageStatus.error
                    ? () => _retryMessage(message)
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // BOTTOM BAR
  // ------------------------------------------------------------

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
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
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.add,
                    color: Colors.white70,
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      onTap: () {
                        if (_voiceState == BetaVoiceState.listening) {
                          _stopListening(endSession: true);
                        }
                      },
                      onSubmitted: (_) => _sendMessage(viaVoice: false),
                      textInputAction: TextInputAction.send,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        hintText: _voiceState == BetaVoiceState.listening
                            ? 'Listening…'
                            : 'Ask Beta',
                        hintStyle: const TextStyle(
                          color: Colors.white54,
                          fontSize: 16,
                        ),
                        border: InputBorder.none,
                        isCollapsed: true,
                      ),
                    ),
                  ),

                  InkWell(
                    onTap: () async {
                      if (_voiceState == BetaVoiceState.listening) {
                        await _stopListening(endSession: true);
                      } else {
                        await _startListening(userInitiated: true);
                      }
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        _voiceState == BetaVoiceState.listening
                            ? Icons.stop
                            : Icons.mic_none,
                        color: _voiceState == BetaVoiceState.listening
                            ? Colors.redAccent
                            : Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 12),

          Material(
            color: Colors.white,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _sendMessage(viaVoice: false),
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

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),

            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                child: _hasConversation ? _buildChatList() : _buildOrbHero(),
              ),
            ),

            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // DISPOSE
  // ------------------------------------------------------------

  @override
  void dispose() {
    _streamSub?.cancel();

    _decayTicker?.cancel();

    _speech.stop();
    _tts.stop();

    _pulseController.dispose();

    _inputController.dispose();
    _scrollController.dispose();

    _chatApi.dispose();

    super.dispose();
  }
}
