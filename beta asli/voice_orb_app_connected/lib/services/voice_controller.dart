// Fixed STT/TTS pipeline for the Beta voice orb.
//
// Root causes this controller fixes (see VOICE_FIXES.md for the full
// analysis of the bugs in voice_home_page.dart):
//
// 1. STT "permanent recognition errors":
//    Android 6+ requires a RUNTIME microphone grant. RECORD_AUDIO in the
//    manifest is not enough. If the user denied the OS dialog once,
//    SpeechToText.initialize() fails on every later call and the app only
//    shows a generic error. We request the permission explicitly and
//    detect permanent denial (must be fixed in OS settings).
//
// 2. doneNoResult / error_no_match killing the hands-free loop:
//    with cancelOnError: false the old code did nothing when the
//    recognizer ended without a result - the loop silently died. We
//    restart listening (bounded: 2 consecutive empty results) while the
//    voice session is active.
//
// 3. "Audio levels but no recognition":
//    the old orb level was FAKE (random bumps on partial results plus
//    a decay ticker). It pulsed even when the microphone captured
//    nothing. We drive the level from SpeechToText's real
//    onSoundLevelChange (actual dB readings), so the UI reflects the
//    real microphone.
//
// 4. TTS finishing silently without speaking:
//    awaitSpeakCompletion(true) + speak() resolving is NOT proof audio
//    played - on devices with a missing/broken TTS engine (and on many
//    emulators) speak() resolves and nothing is audible. We register
//    start/completion/error handlers and only treat a response as spoken
//    once the platform start handler fires (with a timeout fallback so a
//    broken engine surfaces a real error).
//
// 5. Recognizer never emitting a final result:
//    some devices ignore the pauseFor silence window and keep returning
//    partials until the hard listenFor cutoff, forcing the user to tap
//    a button to submit. This controller now runs its OWN silence
//    debounce: every speech activity (partial transcript or real audio
//    level) restarts [silenceTimeout]; when it fires with a transcript
//    in hand, the best transcript is finalized through the same
//    onFinalTranscript path the recognizer's own final result uses.
//    Auto-submit is therefore deterministic on every device.

import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// High-level assistant state, matching the orb's five states.
enum VoiceState { idle, listening, processing, speaking, error }

class VoiceController {
  VoiceController({
    this.onStateChanged,
    this.onLevelChanged,
    this.onPartialTranscript,
    this.onFinalTranscript,
    this.onError,
    this.silenceTimeout = const Duration(seconds: 10),
  });

  final void Function(VoiceState state)? onStateChanged;
  final void Function(double level)? onLevelChanged;
  final void Function(String transcript)? onPartialTranscript;
  final void Function(String transcript)? onFinalTranscript;
  final void Function(String message)? onError;

  /// How long the user may fall silent before the controller treats the
  /// utterance as complete and submits it automatically. Restarted by
  /// every partial transcript and every non-trivial audio level, so it
  /// measures "time since the user last spoke", not time since listen
  /// started. Default 10s per product request.
  final Duration silenceTimeout;

  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _initialized = false;
  bool _available = false;
  bool _handsFreeSession = false;
  bool _listenInProgress = false;
  bool _disposed = false;

  /// Consecutive recognizer endings with no captured speech.
  int _consecutiveNoResults = 0;
  static const int _maxConsecutiveNoResults = 2;

  /// Best transcript seen so far in the current listen window; finalized
  /// by the silence debounce if the recognizer never emits finalResult.
  String _latestTranscript = '';

  /// The silence debounce itself; null while no speech has been captured.
  Timer? _silenceTimer;

  /// Level above which incoming audio counts as "the user is speaking"
  /// (background hiss stays below this on typical phone mics).
  static const double _speechLevelThreshold = 0.15;

  /// Guard so the debounce and the recognizer's own final result can't
  /// both finalize the same utterance.
  bool _finalizing = false;

  /// Completion signal for "speech actually started".
  Completer<bool>? _ttsStartCompleter;

  VoiceState _state = VoiceState.idle;
  VoiceState get state => _state;

  bool get isListening => _listenInProgress || _speech.isListening;

  // =========================================================================
  // INITIALIZATION
  // =========================================================================

  /// Requests the microphone permission and initializes STT + TTS.
  ///
  /// Returns true when speech recognition is usable. On permanent denial
  /// [onError] receives a message telling the user to enable the
  /// microphone in OS settings - that is a settings fix, not an app bug.
  Future<bool> initialize() async {
    if (_initialized) return _available;
    _initialized = true;

    // ---- 1. Runtime microphone permission -------------------------------
    final PermissionStatus status = await Permission.microphone.request();
    if (!status.isGranted) {
      _notifyError(
        status.isPermanentlyDenied
            ? 'Microphone access is blocked. Enable it for Beta in your '
                'device settings, then try again.'
            : 'Microphone permission is required to talk to Beta.',
      );
      return false;
    }

    // ---- 2. Speech recognizer --------------------------------------------
    // NOTE: onSoundLevelChange belongs to listen(), NOT initialize() in
    // speech_to_text 7.x - the real dB readings are wired there instead.
    _available = await _speech.initialize(
      onError: _handleSttError,
      onStatus: _handleSttStatus,
      debugLogging: true,
    );

    if (!_available) {
      _notifyError(
        'Speech recognition is unavailable on this device. If you are on '
        'an emulator, use a physical device or configure a virtual '
        'microphone - emulators usually have no speech service.',
      );
      return false;
    }

    // ---- 3. TTS engine + handlers ----------------------------------------
    await _configureTts();

    return _available;
  }

  Future<void> _configureTts() async {
    try {
      // Surface real engine failures instead of a silent no-op speak().
      // NOTE: the set*Handler setters return void in this flutter_tts
      // version - do NOT await them.
      _tts.setStartHandler(() {
        final Completer<bool>? completer = _ttsStartCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete(true);
        }
      });

      _tts.setCompletionHandler(() {
        final Completer<bool>? completer = _ttsStartCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete(true);
        }
      });

      // flutter_tts's ErrorHandler typedef is dynamic, not Object.
      _tts.setErrorHandler((dynamic message) {
        final Completer<bool>? completer = _ttsStartCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete(false);
        }
      });

      _tts.setCancelHandler(() {
        final Completer<bool>? completer = _ttsStartCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete(false);
        }
      });

      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
      try {
        await _tts.setLanguage('en-US');
      } catch (_) {
        // Non-fatal: fall back to the engine's default language.
      }
    } catch (_) {
      // A missing/broken engine shows up here; keep going so speak()
      // reports a real failure via its start-handler timeout.
    }
  }

  // =========================================================================
  // LISTENING
  // =========================================================================

  Future<void> startListening({bool handsFree = false}) async {
    if (_disposed) return;
    if (_listenInProgress || _speech.isListening) return;

    if (!_initialized) {
      final bool ok = await initialize();
      if (!ok) return;
    }
    if (!_available) return;

    // Never open the mic while the speaker is still holding audio focus.
    try {
      await _tts.stop();
    } catch (_) {}

    _handsFreeSession = _handsFreeSession || handsFree;
    _consecutiveNoResults = 0;
    _latestTranscript = '';
    _finalizing = false;
    _listenInProgress = true;
    _setState(VoiceState.listening);

    try {
      await _speech.listen(
        onResult: _handleSttResult,
        // Real microphone dB readings drive the orb - no fake pulses.
        // This is a listen() parameter in speech_to_text 7.x.
        onSoundLevelChange: _handleSoundLevel,
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 30),
          // 3s of silence ends the turn - long enough for elderly users
          // to finish a sentence, short enough to avoid recognizer drift.
          // Devices that ignore this are covered by the controller's own
          // silence debounce (see _resetSilenceTimer).
          pauseFor: const Duration(seconds: 3),
          cancelOnError: false,
          partialResults: true,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      _listenInProgress = false;
      _notifyError('Unable to start the microphone.');
    }
  }

  /// Real mic dB readings -> 0..1 orb level. Values differ per platform;
  // this mapping works for typical Android/iOS speech input levels.
  void _handleSoundLevel(double levelDb) {
    if (_disposed) return;
    final double normalized = ((levelDb + 2.0) / 12.0).clamp(0.0, 1.0);
    onLevelChanged?.call(normalized);

    // Real voice above the noise floor counts as speech activity and
    // keeps the silence debounce from cutting the user off mid-sentence
    // even when the recognizer hasn't produced a partial yet.
    if (normalized > _speechLevelThreshold && _listenInProgress) {
      _resetSilenceTimer();
    }
  }

  Future<void> stopListening() async {
    _cancelSilenceTimer();
    _handsFreeSession = false;
    _listenInProgress = false;
    try {
      await _speech.stop();
    } catch (_) {}
    onLevelChanged?.call(0.0);
    _setState(VoiceState.idle);
  }

  // =========================================================================
  // SILENCE DEBOUNCE (auto-finalize)
  // =========================================================================

  /// Restarts the silence countdown. Any partial transcript or audible
  /// input calls this; when the timer finally fires, the utterance is
  /// treated as complete and submitted automatically.
  void _resetSilenceTimer() {
    if (_disposed || _finalizing) return;
    _silenceTimer?.cancel();
    _silenceTimer = Timer(silenceTimeout, _onSilenceElapsed);
  }

  void _cancelSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
  }

  Future<void> _onSilenceElapsed() async {
    _silenceTimer = null;
    if (_disposed || _finalizing) return;
    if (!_listenInProgress) return;
    final String transcript = _latestTranscript.trim();
    if (transcript.isEmpty) return;

    // The recognizer ignored its own pauseFor window (device-dependent)
    // or is still streaming partials - finalize manually through the
    // exact same path a native finalResult would take, so the UI and
    // the hands-free loop behave identically.
    _finalizing = true;
    _listenInProgress = false;
    try {
      await _speech.stop();
    } catch (_) {}
    _setState(VoiceState.processing);
    onFinalTranscript?.call(transcript);
  }

  void _handleSttResult(SpeechRecognitionResult result) {
    if (_disposed || _finalizing) return;
    final String text = result.recognizedWords.trim();
    final bool isFinal = result.finalResult;

    if (text.isNotEmpty) {
      _consecutiveNoResults = 0;
      if (isFinal) {
        // Native final result wins; the debounce must not double-submit.
        _cancelSilenceTimer();
        _listenInProgress = false;
        _setState(VoiceState.processing);
        onFinalTranscript?.call(text);
      } else {
        _latestTranscript = text;
        onPartialTranscript?.call(text);
        _resetSilenceTimer();
      }
    }
  }

  void _handleSttStatus(String status) {
    if (_disposed) return;

    if (status == 'listening') {
      _listenInProgress = true;
      return;
    }

    if (status == 'done' || status == 'notListening') {
      _cancelSilenceTimer();

      // A final result (or the debounce) sets _listenInProgress=false
      // BEFORE the status arrives, so "still in progress" means no speech
      // was captured.
      final bool hadResult = !_listenInProgress;
      _listenInProgress = false;
      onLevelChanged?.call(0.0);

      // The old code stopped here: a recognizer ending with no speech
      // (doneNoResult) silently killed the hands-free loop. Restart with
      // a bound so a dead microphone cannot loop forever.
      if (!hadResult && _handsFreeSession && _state == VoiceState.listening) {
        _consecutiveNoResults += 1;
        if (_consecutiveNoResults <= _maxConsecutiveNoResults) {
          _scheduleRestart();
          return;
        }
        _handsFreeSession = false;
        _notifyError("Beta didn't catch that. Tap the orb to speak again.");
      } else if (!_handsFreeSession) {
        _setState(VoiceState.idle);
      }
    }
  }

  Future<void> _scheduleRestart() async {
    // Give the recognizer a moment to fully release before re-listening;
    // immediate re-listen calls are a known source of permanent
    // recognizer errors on Android.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (_disposed || !_handsFreeSession || _listenInProgress) return;
    if (_state != VoiceState.listening) return;
    _latestTranscript = '';
    _finalizing = false;
    try {
      await _speech.listen(
        onResult: _handleSttResult,
        onSoundLevelChange: _handleSoundLevel,
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          cancelOnError: false,
          partialResults: true,
          listenMode: ListenMode.dictation,
        ),
      );
      _listenInProgress = true;
    } catch (_) {
      _handsFreeSession = false;
      _setState(VoiceState.idle);
    }
  }

  void _handleSttError(dynamic error) {
    if (_disposed) return;
    final String errorText = error.toString().toLowerCase();

    if (errorText.contains('error_no_match') ||
        errorText.contains('error_speech_timeout')) {
      // Expected, not a fault: nothing intelligible was captured.
      _cancelSilenceTimer();
      _listenInProgress = false;
      if (_handsFreeSession &&
          _consecutiveNoResults < _maxConsecutiveNoResults) {
        _consecutiveNoResults += 1;
        _scheduleRestart();
      } else {
        _handsFreeSession = false;
        _setState(VoiceState.idle);
      }
      return;
    }

    if (errorText.contains('permission') ||
        errorText.contains('denied') ||
        errorText.contains('not_allowed')) {
      _cancelSilenceTimer();
      _handsFreeSession = false;
      _listenInProgress = false;
      _notifyError(
        'Microphone access was denied. Enable it in device settings and '
        'restart the app.',
      );
      return;
    }

    if (errorText.contains('network') ||
        errorText.contains('network_error')) {
      _cancelSilenceTimer();
      // Android recognition is a Google network service; no connection
      // is a real, reportable failure mode.
      _handsFreeSession = false;
      _listenInProgress = false;
      _notifyError(
        'Speech recognition needs an internet connection. Check your '
        'network and try again.',
      );
      return;
    }

    _cancelSilenceTimer();
    _listenInProgress = false;
    _handsFreeSession = false;
    _notifyError('Voice recognition hit an unexpected error. Tap to retry.');
  }

  // =========================================================================
  // SPEAKING
  // =========================================================================

  /// Speaks [text] and resolves true only when the platform confirmed
  /// playback actually started. A speak() that "succeeds" silently (no
  /// start event) resolves false after the timeout - that is the missing
  /// engine / silent TTS case, reported as a real error.
  Future<bool> speak(String text) async {
    if (_disposed || text.trim().isEmpty) return false;

    try {
      await _speech.stop();
    } catch (_) {}

    _ttsStartCompleter = Completer<bool>();

    try {
      await _tts.speak(text);
    } catch (e) {
      _ttsStartCompleter = null;
      _notifyError('Beta could not speak the response.');
      return false;
    }

    // With awaitSpeakCompletion(true), speak() resolves at completion on
    // most platforms. Race it with the start-handler and a timeout so a
    // broken engine cannot hang the loop or fail silently.
    final bool started = await _ttsStartCompleter!.future
        .timeout(const Duration(seconds: 5), onTimeout: () => false);

    _ttsStartCompleter = null;

    if (!started) {
      _notifyError(
        'Text-to-speech did not start. Check that your device has a TTS '
        'engine enabled (Settings > Text-to-speech) - emulators often '
        'ship without one.',
      );
      return false;
    }
    return true;
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  // =========================================================================
  // LIFECYCLE
  // =========================================================================

  void _setState(VoiceState newState) {
    if (_state == newState) return;
    _state = newState;
    onStateChanged?.call(newState);
  }

  void _notifyError(String message) {
    onLevelChanged?.call(0.0);
    _setState(VoiceState.error);
    onError?.call(message);
  }

  Future<void> dispose() async {
    _disposed = true;
    _cancelSilenceTimer();
    _handsFreeSession = false;
    try {
      await _speech.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
