import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../core/exceptions.dart';
import 'auth_service.dart';

/// One Family Talk message, mirroring the backend's message shape.
class FamilyTalkMessage {
  FamilyTalkMessage({
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

  factory FamilyTalkMessage.fromJson(Map<String, dynamic> json) {
    return FamilyTalkMessage(
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

class FamilyTalkException implements Exception {
  FamilyTalkException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Care-side Family Talk client: the walkie-talkie between the caregiver
/// (this app) and the elder (Beta Asli on their phone).
///
/// Route map (Feature C backend):
/// - history:   GET  /family/conversations/{elder_user_id}/messages
/// - send text: POST /family/messages
/// - upload:    POST /family/voice-notes/upload        (multipart)
/// - send voice:POST /family/voice-messages
/// - mark read: POST /family/messages/read
/// - playback:  GET  /family/voice-notes/{elder_id}/{audio_id}/audio
///   Voice notes use family-media:// URLs and ALWAYS require the auth
///   header, so a leaked URL alone can't play anything.
class FamilyTalkService {
  FamilyTalkService({required this.authService, http.Client? client})
      : _client = client ?? http.Client();

  final AuthService authService;
  final http.Client _client;

  String get _apiV1 => AppConfig.backendBaseUrl;

  Future<Map<String, String>> _headers({bool jsonBody = false}) async {
    final token = await authService.getIdToken();
    if (token.isEmpty) {
      throw const NotSignedInException();
    }
    return {
      'Authorization': 'Bearer $token',
      if (jsonBody) 'Content-Type': 'application/json',
    };
  }

  // ------------------------------------------------------------------
  // Circle discovery
  // ------------------------------------------------------------------

  /// My user id via the backend's auth profile.
  Future<String> myUserId() async {
    final response = await _client
        .get(Uri.parse('$_apiV1/auth/profile'), headers: await _headers())
        .timeout(AppConfig.apiTimeout);
    _throwOnHttpError(response, 'load profile');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['id'] as String;
  }

  /// Elders this caregiver is linked to (from the care circles).
  Future<List<String>> myElders() async {
    final response = await _client
        .get(Uri.parse('$_apiV1/care-circles/my-elders'),
            headers: await _headers())
        .timeout(AppConfig.apiTimeout);
    _throwOnHttpError(response, 'load elders');
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => (e as Map<String, dynamic>)['elder_user_id'] as String)
        .toList();
  }

  // ------------------------------------------------------------------
  // Messages
  // ------------------------------------------------------------------

  Future<List<FamilyTalkMessage>> history(String elderUserId,
      {int limit = 50}) async {
    final response = await _client
        .get(
          Uri.parse(
              '$_apiV1/family/conversations/$elderUserId/messages?limit=$limit'),
          headers: await _headers(),
        )
        .timeout(AppConfig.apiTimeout);
    _throwOnHttpError(response, 'load messages');
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((m) =>
            FamilyTalkMessage.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<FamilyTalkMessage> sendText({
    required String elderUserId,
    required String text,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_apiV1/family/messages'),
          headers: await _headers(jsonBody: true),
          body: jsonEncode({'elder_user_id': elderUserId, 'text': text}),
        )
        .timeout(AppConfig.apiTimeout);
    _throwOnHttpError(response, 'send message');
    return FamilyTalkMessage.fromJson(
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
      throw FamilyTalkException(
          'Upload failed (${response.statusCode}): $body');
    }
    return (jsonDecode(body) as Map<String, dynamic>)['audio_url'] as String;
  }

  /// Walkie-talkie step 2: attach the uploaded audio to a message.
  Future<FamilyTalkMessage> sendVoice({
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
        .timeout(AppConfig.apiTimeout);
    _throwOnHttpError(response, 'send voice message');
    return FamilyTalkMessage.fromJson(
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
        .timeout(AppConfig.apiTimeout);
    _throwOnHttpError(response, 'mark read');
  }

  // ------------------------------------------------------------------
  // Playback
  // ------------------------------------------------------------------

  /// A family-media:// URL resolves to the backend's authorized playback
  /// endpoint. Playback must carry the auth header; the URL alone is
  /// never enough to hear a voice note.
  Uri playbackUri(FamilyTalkMessage message) {
    final audioUrl = message.audioUrl;
    if (audioUrl == null) {
      throw FamilyTalkException('Message has no audio.');
    }
    if (!audioUrl.startsWith('family-media://')) {
      throw FamilyTalkException('Unsupported audio source.');
    }
    final rest = audioUrl.substring('family-media://'.length);
    final parts = rest.split('/');
    if (parts.length != 2) {
      throw FamilyTalkException('Unsupported audio source.');
    }
    return Uri.parse('$_apiV1/family/voice-notes/${parts[0]}/${parts[1]}/audio');
  }

  /// The Authorization header just_audio needs for playback.
  Future<Map<String, String>> playbackHeaders() => _headers();

  void dispose() => _client.close();

  void _throwOnHttpError(http.Response response, String what) {
    if (response.statusCode >= 400) {
      throw FamilyTalkException(
          'Could not $what (${response.statusCode}): ${response.body}');
    }
  }
}
