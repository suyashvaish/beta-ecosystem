import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/exceptions.dart';
import '../services/auth_service.dart';

enum AuthStatus { unknown, signedOut, signedIn }

/// Thin ChangeNotifier wrapper around [AuthService] so screens can
/// `context.watch<AuthProvider>()` instead of holding a stream themselves.
class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  StreamSubscription<AuthUser?>? _sub;

  AuthStatus status = AuthStatus.unknown;
  AuthUser? user;
  bool isBusy = false;
  AppException? error;

  AuthProvider(this._authService) {
    _sub = _authService.authStateChanges().listen((u) {
      user = u;
      status = u == null ? AuthStatus.signedOut : AuthStatus.signedIn;
      notifyListeners();
    });
  }

  Future<bool> signIn({required String email, required String password}) => _run(() async {
        await _authService.signIn(email: email, password: password);
      });

  Future<bool> register({required String email, required String password, required String displayName}) =>
      _run(() async {
        await _authService.register(email: email, password: password, displayName: displayName);
      });

  Future<void> signOut() => _authService.signOut();

  Future<bool> _run(Future<void> Function() action) async {
    isBusy = true;
    error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on AppException catch (e) {
      error = e;
      return false;
    } catch (_) {
      error = const UnknownApiException();
      return false;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
