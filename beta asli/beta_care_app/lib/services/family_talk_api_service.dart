import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'auth_service.dart';

/// One elder this caregiver looks after.
class MyElder {
  MyElder({required this.elderUserId, required this.circleRole});

  final String elderUserId;
  final String circleRole;
}

/// One Family Talk message, mirroring the backend's shape (same as the
/// Beta Asli app's model).
class FamilyMessage {
  FamilyMessage({
    required this.id,
    required this.senderUserId,
    required this.senderName,
    required this.messageType,
    this.body,
    this.audioUrl,
    this.durationSeconds,
    this.transcript,
    required this.createdAt,
    required this.read,
  });

  final String id;
  final String senderUserId;
  final String senderName;
  final String messageType; // 'text' | 'voice'
  final String? body;
  final String? audioUrl;
  final int? durationSeconds;
  final String? transcript;
  final DateTime createdAt;
  final bool read;

  factory FamilyMessage.fromJson(Map<String, dynamic> json) {
    return FamilyMessage(
      id: json['id'] as String,
      senderUserId: json['sender_user_id'] as String,
      senderName: (json['sender_name'] as String?) ?? 'Family member',
      messageType: json['message_type'] as String,
      body: json['body'] as String?,
      audioUrl: json['audio_url'] as String?,
      durationSeconds: json['duration_seconds'] as int?,
      transcript: json['transcript'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      read: json['read'] as bool? ?? false,
    );
  }
}

class FamilyTalkApiException implements Exception {
  FamilyTalkApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Family Talk client for the CARE side. Authorization is entirely
/// server-side via circle membership; this class only talks to the
/// same endpoints the Asli app uses.
class FamilyTalkApiService {
  FamilyTalkApiService({required AuthService authService, http.Client? client})
      : _authService = authService,
        _client = client ?? http.Client();

  final AuthService _authService;
  final http.Client _client;

  String get _apiV1 => BackendConfig.apiV1;

  Future<Map<String, String>> _headers({bool jsonBody = false}) async {
    final token = await _authService.idToken;
    if (token == null) {
      throw FamilyTalkApiException('Not signed in.');
    }
    return {
      'Authorization': 'Bearer $token',
      if (jsonBody) 'Content-Type': 'application/json',
    };
  }

  /// Elders this user cares for (circle switching). Empty list means
  /// the caregiver has not joined any circle yet.
  Future<List<MyElder>> myElders() async {
    final response = await _client
        .get(Uri.parse('$_apiV1/care-circles/my-elders'),
            headers: await _headers())
        .timeout(const Duration(seconds: 10));
    _throwOnHttpError(response, 'load your elders');
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => MyElder(
              elderUserId: (e as Map<String, dynamic>)['elder_user_id']
                  as String,
              circleRole:
                  (e)['circle_role'] as String? ?? 'viewer',
            ))
        .toList();
  }

  Future<String> myUserId() async {
    final response = await _client
        .get(Uri.parse('$_apiV1/auth/profile'), headers: await _headers())
        .timeout(const Duration(seconds: 10));
    _throwOnHttpError(response, 'load your profile');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['id'] as String;
  }

  Future<List<FamilyMessage>> history(String elderUserId,
      {int limit = 50}) async {
    final response = await _client
        .get(
          Uri.parse(
              '$_apiV1/family/conversations/$elderUserId/messages?limit=$limit'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 15));
    _throwOnHttpError(response, 'load messages');
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((m) => FamilyMessage.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<FamilyMessage> sendText({
    required String elderUserId,
    required String text,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_apiV1/family/messages'),
          headers: await _headers(jsonBody: true),
          body: jsonEncode({'elder_user_id': elderUserId, 'text': text}),
        )
        .timeout(const Duration(seconds: 15));
    _throwOnHttpError(response, 'send message');
    return FamilyMessage.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Walkie-talkie step 1: upload the recording, get the media URL.
  Future<String> uploadVoiceNote({
    required String elderUserId,
    required File audioFile,
    required int durationSeconds,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_apiV1/family/voice-notes/upload'),
    )
      ..headers.addAll(await _headers())
      ..fields['elder_user_id'] = elderUserId
      ..fields['duration_seconds'] = durationSeconds.toString()
      ..files.add(await http.MultipartFile.fromPath('audio', audioFile.path));

    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    final body = await response.stream.bytesToString();
    if (response.statusCode >= 400) {
      throw FamilyTalkApiException(
          'Upload failed (${response.statusCode}): $body');
    }
    return (jsonDecode(body) as Map<String, dynamic>)['audio_url'] as String;
  }

  /// Walkie-talkie step 2: attach the uploaded audio to a message.
  Future<FamilyMessage> sendVoice({
    required String elderUserId,
    required String audioUrl,
    required int durationSeconds,
    String? transcript,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_apiV1/family/voice-messages'),
          headers: await _headers(jsonBody: true),
          body: jsonEncode({
            'elder_user_id': elderUserId,
            'audio_url': audioUrl,
            'duration_seconds': durationSeconds,
            if (transcript != null) 'transcript': transcript,
          }),
        )
        .timeout(const Duration(seconds: 15));
    _throwOnHttpError(response, 'send voice message');
    return FamilyMessage.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> markRead({
    required String elderUserId,
    required String messageId,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_apiV1/family/messages/read'),
          headers: await _headers(jsonBody: true),
          body: jsonEncode({
            'elder_user_id': elderUserId,
            'message_id': messageId,
          }),
        )
        .timeout(const Duration(seconds: 10));
    _throwOnHttpError(response, 'mark read');
  }

  /// A family-media:// URL resolves to the backend's authorized
  /// playback endpoint; playback always carries the auth header.
  Uri playbackUri(FamilyMessage message) {
    final audioUrl = message.audioUrl;
    if (audioUrl == null) {
      throw FamilyTalkApiException('Message has no audio.');
    }
    if (!audioUrl.startsWith('family-media://')) {
      throw FamilyTalkApiException('Unsupported audio source.');
    }
    final parts = audioUrl.substring('family-media://'.length).split('/');
    if (parts.length != 2) {
      throw FamilyTalkApiException('Unsupported audio source.');
    }
    return Uri.parse('$_apiV1/family/voice-notes/${parts[0]}/${parts[1]}/audio');
  }

  Future<Map<String, String>> playbackHeaders() => _headers();

  void dispose() => _client.close();

  void _throwOnHttpError(http.Response response, String what) {
    if (response.statusCode >= 400) {
      throw FamilyTalkApiException(
          'Could not $what (${response.statusCode}): ${response.body}');
    }
  }
}