/// A push notification already translated into something the UI can show -
/// Beta Care never routes based on raw FCM payload shape outside this layer.
class PushNotification {
  final String title;
  final String body;
  final String? relatedAlertId;

  const PushNotification({required this.title, required this.body, this.relatedAlertId});
}

abstract class NotificationService {
  Future<void> initialize();

  /// Fires when a push notification arrives while the app is open.
  Stream<PushNotification> get onNotification;

  /// The device token the backend should send FCM pushes to. Returns null
  /// on the mock implementation, and on real devices before permission is
  /// granted.
  Future<String?> getDeviceToken();
}

class MockNotificationService implements NotificationService {
  @override
  Future<void> initialize() async {}

  @override
  Stream<PushNotification> get onNotification => const Stream.empty();

  @override
  Future<String?> getDeviceToken() async => null;
}
