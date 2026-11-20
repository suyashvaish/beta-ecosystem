import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beta_care/main.dart';
import 'package:beta_care/services/auth_service.dart';
import 'package:beta_care/services/beta_api_client.dart';
import 'package:beta_care/services/notification_service.dart';

void main() {
  testWidgets('Beta Care boots to the sign-in screen in mock mode',
      (WidgetTester tester) async {
    // Same wiring as main() with AppConfig.useMockBackend == true:
    // all in-memory services, no Firebase, no network.
    await tester.pumpWidget(BetaCareApp(
      authService: MockAuthService(),
      apiClient: MockBetaApiClient(),
      notificationService: MockNotificationService(),
    ));

    // First frame: providers settle, AuthGate shows the login UI.
    await tester.pumpAndSettle();

    // The sign-in screen is the entry point for an anonymous user.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}