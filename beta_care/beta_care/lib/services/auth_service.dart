import 'dart:async';

import '../core/exceptions.dart';

/// A minimal view of the signed-in caregiver's Firebase identity. Beta Care
/// only ever needs the uid, email, and a token to hand to the backend - it
/// never touches Firestore or any database directly (section 21).
class AuthUser {
  final String uid;
  final String email;
  final String displayName;

  const AuthUser({required this.uid, required this.email, required this.displayName});
}

abstract class AuthService {
  /// Fires whenever sign-in state changes, including once at startup.
  Stream<AuthUser?> authStateChanges();

  AuthUser? get currentUser;

  Future<AuthUser> signIn({required String email, required String password});

  Future<AuthUser> register({required String email, required String password, required String displayName});

  Future<void> signOut();

  /// The Firebase ID token to send as `Authorization: Bearer <token>` on
  /// every backend request (section 19's auth flow).
  Future<String> getIdToken();
}

/// Fully in-memory implementation used whenever [AppConfig.useMockBackend]
/// is true, so the app is demoable with no Firebase project configured.
class MockAuthService implements AuthService {
  AuthUser? _user;
  final _controller = StreamController<AuthUser?>.broadcast();

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield _user;
    yield* _controller.stream;
  }

  @override
  Future<AuthUser> signIn({required String email, required String password}) async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (password.length < 6) {
      throw const UnknownApiException('Incorrect email or password.');
    }
    _user = AuthUser(uid: 'mock-caregiver-1', email: email, displayName: 'Priya Sharma');
    _controller.add(_user);
    return _user!;
  }

  @override
  Future<AuthUser> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    _user = AuthUser(uid: 'mock-caregiver-1', email: email, displayName: displayName);
    _controller.add(_user);
    return _user!;
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }

  @override
  Future<String> getIdToken() async => 'mock-id-token';
}
