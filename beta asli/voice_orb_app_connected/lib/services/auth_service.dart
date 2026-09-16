import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'settings_service.dart';

/// Thin wrapper around Firebase Auth, plus the one call the backend expects
/// right after a successful sign-in (`POST /auth/sign-in`) to provision the
/// local `User` row. (The backend also lazily auto-provisions on first
/// authenticated request, but calling sign-in explicitly matches the
/// intended flow and surfaces auth errors immediately, before the user
/// starts chatting.)
class AuthService {
  AuthService({FirebaseAuth? firebaseAuth})
      : _auth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Fresh Firebase ID token for the current user, or null if signed out.
  /// Every authenticated backend call needs this in the Authorization header.
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

  /// Calls POST /auth/sign-in so the backend provisions/find the local
  /// User row right away. Non-fatal if it fails — get_current_user()
  /// will lazily provision on the first chat call anyway — but we surface
  /// network errors here so the login screen can show them immediately
  /// rather than confusing the user later on the chat screen.
  Future<void> _provisionOnBackend() async {
    final token = await idToken;
    if (token == null) return;

    final response = await http
        .post(
          Uri.parse('${SettingsService.instance.backendApiV1}/auth/sign-in'),
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

class AuthBackendException implements Exception {
  AuthBackendException(this.message);
  final String message;
  @override
  String toString() => message;
}
