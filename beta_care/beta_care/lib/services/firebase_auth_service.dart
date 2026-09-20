import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../core/exceptions.dart';
import 'auth_service.dart';

/// Real implementation, wired in once `AppConfig.useMockBackend = false`
/// and Firebase has been initialized in main.dart. Never stores or reads
/// backend credentials - it only produces the Firebase ID token that the
/// backend itself verifies (section 19 / 21).
class FirebaseAuthService implements AuthService {
  final fb.FirebaseAuth _auth;

  FirebaseAuthService({fb.FirebaseAuth? auth}) : _auth = auth ?? fb.FirebaseAuth.instance;

  AuthUser? _toAuthUser(fb.User? user) {
    if (user == null) return null;
    return AuthUser(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName ?? '',
    );
  }

  @override
  AuthUser? get currentUser => _toAuthUser(_auth.currentUser);

  @override
  Stream<AuthUser?> authStateChanges() => _auth.authStateChanges().map(_toAuthUser);

  @override
  Future<AuthUser> signIn({required String email, required String password}) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(email: email, password: password);
      final user = _toAuthUser(credential.user);
      if (user == null) throw const NotSignedInException();
      return user;
    } on fb.FirebaseAuthException catch (e) {
      throw UnknownApiException(_messageFor(e));
    }
  }

  @override
  Future<AuthUser> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      await credential.user?.updateDisplayName(displayName);
      final user = _toAuthUser(credential.user);
      if (user == null) throw const NotSignedInException();
      return AuthUser(uid: user.uid, email: user.email, displayName: displayName);
    } on fb.FirebaseAuthException catch (e) {
      throw UnknownApiException(_messageFor(e));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<String> getIdToken() async {
    final token = await _auth.currentUser?.getIdToken();
    if (token == null) throw const NotSignedInException();
    return token;
  }

  String _messageFor(fb.FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists with that email.';
      case 'weak-password':
        return 'Please choose a stronger password.';
      case 'network-request-failed':
        return 'Unable to connect. Please check your internet connection.';
      default:
        return 'Something went wrong while signing in. Please try again.';
    }
  }
}
