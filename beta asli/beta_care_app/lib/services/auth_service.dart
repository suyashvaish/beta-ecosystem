import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Thin wrapper around Firebase Auth plus the one backend call
/// (`POST /auth/sign-in`) that provisions the local User row. Copied
/// from the Beta Asli app - same Firebase project, same backend.
class AuthService {
  AuthService({FirebaseAuth? firebaseAuth})
      : _auth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<String?> get idToken async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _provisionOnBackend();
    return credential;
  }

  Future<UserCredential> signUp({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _provisionOnBackend();
    return credential;
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> _provisionOnBackend() async {
    final token = await idToken;
    if (token == null) return;

    final response = await http
        .post(
          Uri.parse('${BackendConfig.apiV1}/auth/sign-in'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'id_token': token}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode >= 400) {
      throw AuthBackendException(
        'Backend rejected sign-in (${response.statusCode}): ${response.body}',
      );
    }
  }
}

/// Backend URL. In development pass it at build time:
///
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.12:8000
///
/// The define is optional so `flutter analyze` / tests run without a
/// network; anything that actually calls the API should fail fast with
/// a clear message when it is missing.
class BackendConfig {
  static const String apiBase = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String get apiV1 =>
      apiBase.endsWith('/') ? '${apiBase}api/v1' : '$apiBase/api/v1';

  static void requireConfigured() {
    if (apiBase.isEmpty) {
      throw StateError(
        'API_BASE_URL not set. Run with '
        '--dart-define=API_BASE_URL=http://<your-mac-ip>:8000',
      );
    }
  }
}

class AuthBackendException implements Exception {
  AuthBackendException(this.message);
  final String message;
  @override
  String toString() => message;
}