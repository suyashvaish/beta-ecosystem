/// Every exception the API/auth layer throws carries a message that's
/// already safe and friendly to show directly in the UI (section 26: never
/// surface a raw status code or stack trace to the caregiver).
abstract class AppException implements Exception {
  final String message;
  const AppException(this.message);

  @override
  String toString() => message;
}

class UnauthorizedException extends AppException {
  const UnauthorizedException([super.message = "You don't currently have permission to view this information."]);
}

class NotSignedInException extends AppException {
  const NotSignedInException([super.message = 'Please sign in again to continue.']);
}

class NetworkException extends AppException {
  const NetworkException([super.message = 'Unable to connect to Beta right now. Please check your internet connection.']);
}

class NotFoundException extends AppException {
  const NotFoundException([super.message = "We couldn't find that information."]);
}

class UnknownApiException extends AppException {
  const UnknownApiException([super.message = 'Something went wrong on our end. Please try again.']);
}
