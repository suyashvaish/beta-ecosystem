import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_config.dart';
import 'core/auth_gate.dart';
import 'core/theme.dart';
import 'firebase_options.dart';
import 'providers/alerts_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/device_provider.dart';
import 'providers/family_provider.dart';
import 'providers/health_provider.dart';
import 'providers/location_provider.dart';
import 'providers/medication_provider.dart';
import 'providers/notification_settings_provider.dart';
import 'providers/permissions_provider.dart';
import 'services/auth_service.dart';
import 'services/beta_api_client.dart';
import 'services/firebase_auth_service.dart';
import 'services/firebase_notification_service.dart';
import 'services/http_beta_api_client.dart';
import 'services/notification_service.dart';

/// FCM background handler. Top-level (not a method) because Dart may
/// invoke it while the app itself isn't running.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  late final AuthService authService;
  late final BetaApiClient apiClient;
  late final NotificationService notificationService;

  if (AppConfig.useMockBackend) {
    authService = MockAuthService();
    apiClient = MockBetaApiClient();
    notificationService = MockNotificationService();
  } else {
    // Real deployment: same Firebase project as Beta Asli
    // (google-services.json / GoogleService-Info.plist are already in
    // the platform folders).
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
    authService = FirebaseAuthService();
    apiClient = HttpBetaApiClient(authService: authService);
    notificationService = FirebaseNotificationService();
  }

  await notificationService.initialize();

  runApp(BetaCareApp(
    authService: authService,
    apiClient: apiClient,
    notificationService: notificationService,
  ));
}

class BetaCareApp extends StatelessWidget {
  final AuthService authService;
  final BetaApiClient apiClient;
  final NotificationService notificationService;

  const BetaCareApp({
    super.key,
    required this.authService,
    required this.apiClient,
    required this.notificationService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>.value(value: authService),
        Provider<BetaApiClient>.value(value: apiClient),
        Provider<NotificationService>.value(value: notificationService),
        ChangeNotifierProvider(create: (_) => AuthProvider(authService)),
        ChangeNotifierProvider(create: (_) => FamilyProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => PermissionsProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => DashboardProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => HealthProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => MedicationProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => LocationProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => DeviceProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => AlertsProvider(apiClient, notificationService)),
        ChangeNotifierProvider(create: (_) => NotificationSettingsProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
      ],
      child: MaterialApp(
        title: 'Beta Care',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: const AuthGate(),
      ),
    );
  }
}
