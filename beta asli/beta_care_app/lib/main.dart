import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/elder_picker_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? firebaseInitError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    firebaseInitError = 'Firebase failed to initialize:\n$e';
  }

  runApp(BetaCareApp(firebaseInitError: firebaseInitError));
}

class BetaCareApp extends StatelessWidget {
  const BetaCareApp({super.key, required this.firebaseInitError});

  final String? firebaseInitError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beta Care',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8755FF),
          brightness: Brightness.dark,
          surface: const Color(0xFF101329),
          onSurface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFF08091D),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8755FF),
          brightness: Brightness.dark,
          surface: const Color(0xFF101329),
          onSurface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFF08091D),
      ),
      themeMode: ThemeMode.dark,
      home: firebaseInitError != null
          ? _SetupNeededScreen(message: firebaseInitError!)
          : AuthGate(authService: AuthService()),
    );
  }
}

/// Routes between login and the elder picker based on auth state.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.authService});

  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF08091D),
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          return LoginScreen(authService: authService);
        }
        return ElderPickerScreen(authService: authService);
      },
    );
  }
}

class _SetupNeededScreen extends StatelessWidget {
  const _SetupNeededScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08091D),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_suggest,
                    color: Colors.white70, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Setup needed',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}