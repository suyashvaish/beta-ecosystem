/// Central place to flip Beta Care from demo mode to a real deployment.
///
/// By default the app runs against the real Beta backend. Point it at
/// your machine with --dart-define=API_BASE_URL=http://lan-ip:8000
/// (the value must include the /api/v1 suffix - match what Beta Asli
/// uses in its settings).
///
/// To demo without a backend, pass --dart-define=USE_MOCK=true and the
/// app runs on the in-memory mock services - no Firebase project, no
/// backend, no network needed.
class AppConfig {
  AppConfig._();

  /// True to run entirely on the in-memory mock services (demo mode).
  /// Overridable at build time so demo builds stay one flag away.
  static const bool useMockBackend =
      bool.fromEnvironment('USE_MOCK', defaultValue: false);

  /// Base URL of the Beta backend API (routes are relative to this).
  /// The LAN default matches the development machine; override with
  /// --dart-define=API_BASE_URL=... when the network changes.
  static const String backendBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.1.12:8000/api/v1',
  );

  static const Duration apiTimeout = Duration(seconds: 15);

  /// How stale a last-synchronized timestamp has to be before the UI
  /// treats it as needing attention rather than just showing the time.
  static const Duration staleDataThreshold = Duration(hours: 2);
}
