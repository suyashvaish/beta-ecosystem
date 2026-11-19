/// Who sent a chat message.
enum ChatRole { user, assistant }

/// Lifecycle of a message as it appears in the chat list.
///
/// User messages are always [complete] the moment they're added.
/// Assistant messages start as [streaming] (empty, then filled in as
/// chunks arrive), then become [complete] on the stream's done event,
/// or [error] if the stream failed.
enum ChatMessageStatus { complete, streaming, error }

/// A single turn in the conversation shown in the chat list.
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    this.text = '',
    this.status = ChatMessageStatus.complete,
    DateTime? time,
    this.viaVoice = false,
  }) : time = time ?? DateTime.now();

  final String id;
  final ChatRole role;
  String text;
  ChatMessageStatus status;

  /// When the turn happened; defaults to now at creation time.
  final DateTime time;

  /// True when this turn came in through the microphone (STT) rather
  /// than the keyboard. Drives the small mic marker in the chat UI.
  final bool viaVoice;
}
