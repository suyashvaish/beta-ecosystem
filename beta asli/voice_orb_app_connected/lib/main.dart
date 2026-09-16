import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/login_screen.dart';

import 'screens/voice_home_page.dart';
import 'services/auth_service.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted settings (backend URL, theme, wake word, etc.) before
  // the first frame so every screen sees the user's saved values right
  // away instead of a flash of defaults.
  await SettingsService.instance.load();

  String? firebaseInitError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    firebaseInitError = 'Firebase failed to initialize:\n$e';
  }

  runApp(VoiceOrbApp(firebaseInitError: firebaseInitError));
}

class VoiceOrbApp extends StatefulWidget {
  const VoiceOrbApp({super.key, this.firebaseInitError});

  final String? firebaseInitError;

  @override
  State<VoiceOrbApp> createState() => _VoiceOrbAppState();
}

class _VoiceOrbAppState extends State<VoiceOrbApp> {
  @override
  void initState() {
    super.initState();
    // Rebuild (e.g. to pick up a new theme) whenever a setting changes.
    SettingsService.instance.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beta',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: SettingsService.instance.flutterThemeMode,
      home: widget.firebaseInitError != null
          ? _SetupNeededScreen(message: widget.firebaseInitError!)
          : AuthGate(authService: AuthService()),
    );
  }
}

/// Routes between the login screen and the voice UI based on Firebase
/// auth state, so the app reacts immediately to sign-in / sign-out.
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
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          return LoginScreen(authService: authService);
        }
        return VoiceHomePage(authService: authService);
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
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_suggest, color: Colors.white54, size: 48),
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
                  style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
