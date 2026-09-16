import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

/// How the app should pick its Material theme brightness.
enum AppThemeMode { system, light, dark }

/// Loads every user-configurable setting once at startup and persists
/// changes immediately via SharedPreferences.
///
/// This is a singleton ([SettingsService.instance]) so any screen can
/// read the current values synchronously after [load] has run once in
/// `main()`, and a [ChangeNotifier] so the root [MaterialApp] can react
/// live to theme/appearance changes made from the Settings screen.
class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  late SharedPreferences _prefs;
  bool _loaded = false;
  bool get isLoaded => _loaded;

  // ---- Keys ----------------------------------------------------------
  static const _kBackendUrl = 'settings.backend_url';
  static const _kAiModel = 'settings.ai_model';
  static const _kVoice = 'settings.voice';
  static const _kWakeWord = 'settings.wake_word';
  static const _kSpeechSpeed = 'settings.speech_speed';
  static const _kThemeMode = 'settings.theme_mode'; // AppThemeMode.name
  static const _kNotifications = 'settings.notifications_enabled';
  static const _kMicSensitivity = 'settings.mic_sensitivity';
  static const _kConversationMemory = 'settings.conversation_memory_enabled';
  static const _kAutoSpeak = 'settings.auto_speak_enabled';

  // ---- Defaults --------------------------------------------------------
  static const String defaultAiModel = 'gpt-4o-mini';
  static const String defaultVoice = 'Default';
  static const String defaultWakeWord = 'Beta';
  static const double defaultSpeechSpeed = 1.0;
  static const double defaultMicSensitivity = 0.5;

  /// Must be called once, before [runApp], e.g.:
  /// `await SettingsService.instance.load();`
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _loaded = true;
    notifyListeners();
  }

  // ---- Backend URL --------------------------------------------------------
  /// Falls back to the compiled-in [ApiConfig.baseUrl] until the user
  /// overrides it from Settings.
  String get backendUrl {
    final stored = _prefs.getString(_kBackendUrl);
    return (stored == null || stored.isEmpty) ? ApiConfig.baseUrl : stored;
  }

  String get backendApiV1 {
    final base = backendUrl;
    return base.endsWith('/') ? '${base}api/v1' : '$base/api/v1';
  }

  Future<void> setBackendUrl(String value) =>
      _set(_kBackendUrl, value.trim());

  // ---- AI model -----------------------------------------------------------
  String get aiModel => _prefs.getString(_kAiModel) ?? defaultAiModel;
  Future<void> setAiModel(String value) => _set(_kAiModel, value);

  // ---- Voice selection ------------------------------------------------
  String get voice => _prefs.getString(_kVoice) ?? defaultVoice;
  Future<void> setVoice(String value) => _set(_kVoice, value);

  // ---- Wake word ------------------------------------------------------
  String get wakeWord => _prefs.getString(_kWakeWord) ?? defaultWakeWord;
  Future<void> setWakeWord(String value) => _set(
        _kWakeWord,
        value.trim().isEmpty ? defaultWakeWord : value.trim(),
      );

  // ---- Speech speed (0.5x - 2.0x) --------------------------------------
  double get speechSpeed => _prefs.getDouble(_kSpeechSpeed) ?? defaultSpeechSpeed;
  Future<void> setSpeechSpeed(double value) => _set(_kSpeechSpeed, value);

  // ---- Theme ------------------------------------------------------------
  AppThemeMode get themeMode {
    final raw = _prefs.getString(_kThemeMode);
    return AppThemeMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => AppThemeMode.dark,
    );
  }

  Future<void> setThemeMode(AppThemeMode mode) =>
      _set(_kThemeMode, mode.name);

  ThemeMode get flutterThemeMode {
    switch (themeMode) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }

  // ---- Notifications ------------------------------------------------------
  bool get notificationsEnabled => _prefs.getBool(_kNotifications) ?? true;
  Future<void> setNotificationsEnabled(bool value) =>
      _set(_kNotifications, value);

  // ---- Microphone sensitivity (0.0 - 1.0) --------------------------------
  double get micSensitivity =>
      _prefs.getDouble(_kMicSensitivity) ?? defaultMicSensitivity;
  Future<void> setMicSensitivity(double value) =>
      _set(_kMicSensitivity, value);

  // ---- Conversation memory ------------------------------------------------
  bool get conversationMemoryEnabled =>
      _prefs.getBool(_kConversationMemory) ?? true;
  Future<void> setConversationMemoryEnabled(bool value) =>
      _set(_kConversationMemory, value);

  // ---- Auto speak ---------------------------------------------------------
  bool get autoSpeakEnabled => _prefs.getBool(_kAutoSpeak) ?? false;
  Future<void> setAutoSpeakEnabled(bool value) => _set(_kAutoSpeak, value);

  // ---- Bulk actions ---------------------------------------------------

  /// Clears only the locally-cached conversation transcript, if/when the
  /// app starts caching one locally. Currently conversation history lives
  /// server-side (see ConversationRepository); this is a hook for when a
  /// local cache is added, kept here so the Settings screen has a single
  /// stable place to call.
  Future<void> clearConversationHistory() async {
    // No local conversation cache yet - nothing to clear locally.
    // Reserved for future local persistence.
  }

  /// Clears everything Settings itself owns except the API key/backend
  /// URL (those are connection settings, not "memory").
  Future<void> resetToDefaults() async {
    await _prefs.remove(_kAiModel);
    await _prefs.remove(_kVoice);
    await _prefs.remove(_kWakeWord);
    await _prefs.remove(_kSpeechSpeed);
    await _prefs.remove(_kThemeMode);
    await _prefs.remove(_kNotifications);
    await _prefs.remove(_kMicSensitivity);
    await _prefs.remove(_kConversationMemory);
    await _prefs.remove(_kAutoSpeak);
    notifyListeners();
  }

  Future<void> _set(String key, Object value) async {
    if (value is String) {
      await _prefs.setString(key, value);
    } else if (value is bool) {
      await _prefs.setBool(key, value);
    } else if (value is double) {
      await _prefs.setDouble(key, value);
    }
    notifyListeners();
  }
}
