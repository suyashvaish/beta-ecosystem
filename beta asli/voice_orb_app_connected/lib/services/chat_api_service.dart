import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'settings_service.dart';

/// Events emitted while streaming a chat reply. UI code switches on the
/// runtime type to react appropriately (see VoiceHomePage).
sealed class ChatStreamEvent {}

class ChatConversationStarted extends ChatStreamEvent {
  ChatConversationStarted(this.conversationId);
  final String conversationId;
}

class ChatTextChunk extends ChatStreamEvent {
  ChatTextChunk(this.text);
  final String text;
}

class ChatStreamDone extends ChatStreamEvent {}

class ChatStreamError extends ChatStreamEvent {
  ChatStreamError(this.detail);
  final String detail;
}

/// Talks to the Beta backend's chat endpoints.
class ChatApiService {
  ChatApiService({required AuthService authService, http.Client? client})
      : _authService = authService,
        _client = client ?? http.Client();

  final AuthService _authService;
  final http.Client _client;

  /// Streams one assistant reply via `POST /chat/stream` (SSE).
  ///
  /// Matches the backend's event sequence:
  ///   event: conversation -> {"conversation_id": "..."}   (always first)
  ///   data: {"text": "..."}                                (0+ chunks)
  ///   event: done -> {}                                    (success)
  ///   event: error -> {"detail": "..."}                    (failure)
  Stream<ChatStreamEvent> sendMessageStream({
    required String message,
    String? conversationId,
  }) async* {
    final token = await _authService.idToken;
    if (token == null) {
      yield ChatStreamError('Not signed in.');
      return;
    }

    final request = http.Request(
      'POST',
      Uri.parse('${SettingsService.instance.backendApiV1}/chat/stream'),
    );
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    });
    request.body = jsonEncode({
      'message': message,
      if (conversationId != null) 'conversation_id': conversationId,
    });

    http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(const Duration(seconds: 30));
    } catch (e) {
      yield ChatStreamError('Could not reach the server: $e');
      return;
    }

    if (response.statusCode >= 400) {
      final body = await response.stream.bytesToString();
      yield ChatStreamError('Server error (${response.statusCode}): $body');
      return;
    }

    // Parse the SSE stream: events are separated by a blank line, each
    // event has optional "event: <name>" and "data: <payload>" lines.
    String eventName = 'message';
    final buffer = StringBuffer();

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        // Idle timeout: resets on every line received. If the connection
        // stalls (backend hangs, network drops silently) with no data for
        // this long, fail instead of leaving the UI stuck indefinitely.
        .timeout(
          const Duration(seconds: 45),
          onTimeout: (sink) {
            sink.addError(TimeoutException('No response from the server.'));
            sink.close();
          },
        );

    await for (final line in lines) {
      if (line.isEmpty) {
        // End of one SSE event - dispatch it.
        final data = buffer.toString();
        buffer.clear();
        final parsed = _dispatch(eventName, data);
        if (parsed != null) yield parsed;
        if (parsed is ChatStreamDone || parsed is ChatStreamError) return;
        eventName = 'message';
        continue;
      }
      if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        buffer.write(line.substring(5).trim());
      }
    }
  }

  ChatStreamEvent? _dispatch(String eventName, String data) {
    if (data.isEmpty) return null;
    switch (eventName) {
      case 'conversation':
        final json = jsonDecode(data) as Map<String, dynamic>;
        return ChatConversationStarted(json['conversation_id'] as String);
      case 'done':
        return ChatStreamDone();
      case 'error':
        final json = jsonDecode(data) as Map<String, dynamic>;
        return ChatStreamError(json['detail']?.toString() ?? 'Unknown error');
      case 'message':
      default:
        final json = jsonDecode(data) as Map<String, dynamic>;
        return ChatTextChunk(json['text']?.toString() ?? '');
    }
  }

  void dispose() => _client.close();
}
