/// Central place to flip Beta Care from demo mode to a real deployment.
///
/// With [useMockBackend] true (the default), the app runs entirely on
/// [MockAuthService] / [MockBetaApiClient] / [MockNotificationService] -
/// no Firebase project, no backend, no network needed. Flip it to false
/// once `beta.backendBaseUrl` points at the real Beta backend and a real
/// `google-services.json` / `GoogleService-Info.plist` has been added to
/// the platform folders for Firebase.
class AppConfig {
  AppConfig._();

  static const bool useMockBackend = true;

  /// Base URL of the existing Beta backend (section 20's endpoint list is
  /// relative to this). Ignored while [useMockBackend] is true.
  static const String backendBaseUrl = 'https://api.example.com';

  static const Duration apiTimeout = Duration(seconds: 15);

  /// How stale a "last synchronized" timestamp has to be before the UI
  /// treats it as needing attention rather than just showing the time.
  static const Duration staleDataThreshold = Duration(hours: 2);
}
