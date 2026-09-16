/// Backend connection settings.
///
/// Android emulator -> backend running on the development machine.
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const String apiV1 = '$baseUrl/api/v1';
}