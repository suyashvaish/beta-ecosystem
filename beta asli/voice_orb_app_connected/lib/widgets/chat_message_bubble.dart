import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import 'typing_indicator.dart';

/// One row in the chat list.
///
/// User turns get a right-aligned tinted bubble. Beta's replies are
/// deliberately plain, left-aligned text with no bubble chrome - the
/// spec asks for this to feel like a modern AI assistant, not a
/// messaging app, and giving both sides the same card treatment is
/// exactly the generic look to avoid.
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    this.onRetry,
  });

  final ChatMessage message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (message.role == ChatRole.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 18, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            message.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15.5,
              height: 1.35,
            ),
          ),
        ),
      );
    }

    final isEmpty = message.text.isEmpty;
    final showTyping = isEmpty && message.status == ChatMessageStatus.streaming;

    return Padding(
      padding: const EdgeInsets.only(bottom: 22, right: 32),
      child: GestureDetector(
        onLongPress: message.status == ChatMessageStatus.complete && !isEmpty
            ? () {
                Clipboard.setData(ClipboardData(text: message.text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied'),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            : null,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showTyping)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 5),
                  child: TypingIndicator(),
                )
              else
                Text(
                  message.text,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15.5,
                    height: 1.45,
                  ),
                ),
              if (message.status == ChatMessageStatus.error) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: onRetry,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, size: 15, color: Colors.white54),
                      SizedBox(width: 4),
                      Text(
                        'Retry',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
