import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'notification_service.dart';

/// Real FCM-backed implementation (section 13). Foreground messages are
/// turned into [PushNotification]s on [onNotification]; the app's UI layer
/// decides how to surface them (a snackbar, a badge, a refresh).
///
/// Background/terminated-state handling needs a *top-level* function
/// registered with `FirebaseMessaging.onBackgroundMessage` before
/// `runApp()` - see the commented example in main.dart - because Dart
/// can't invoke an instance method while the app isn't running.
class FirebaseNotificationService implements NotificationService {
  final _controller = StreamController<PushNotification>.broadcast();
  StreamSubscription<RemoteMessage>? _sub;

  @override
  Future<void> initialize() async {
    await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    _sub = FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      _controller.add(PushNotification(
        title: notification.title ?? 'Beta Care',
        body: notification.body ?? '',
        relatedAlertId: message.data['alertId'] as String?,
      ));
    });
  }

  @override
  Stream<PushNotification> get onNotification => _controller.stream;

  @override
  Future<String?> getDeviceToken() => FirebaseMessaging.instance.getToken();

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
