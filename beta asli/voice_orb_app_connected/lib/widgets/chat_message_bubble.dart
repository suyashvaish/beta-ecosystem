import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import '../theme/beta_theme.dart';
import 'typing_indicator.dart';

/// One row in the redesigned chat list.
///
/// Design (reference screenshot 3):
///   - user turns: right-aligned card with a purple border glow
///   - Beta replies: left-aligned plain card with secondary text -
///     the "assistant, not messaging app" feel, now in the new palette
///   - timestamps under each message
///   - small mic marker on turns that came in by voice
///   - long-press copies a completed Beta reply
///
/// Kept as a stateless card; all data comes from [message].
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    this.onRetry,
  });

  final ChatMessage message;
  final VoidCallback? onRetry;

  bool get _isUser => message.role == ChatRole.user;

  String _formatTime(DateTime time) {
    final String h = time.hour.toString().padLeft(2, '0');
    final String m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final bool isEmpty = message.text.isEmpty;
    final bool showTyping =
        isEmpty && message.status == ChatMessageStatus.streaming;

    final Widget content =
        _isUser ? _buildUserBubble() : _buildAssistantCard(context, showTyping);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment:
            _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          content,
          const SizedBox(height: 6),
          _buildMetaRow(),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // USER BUBBLE
  // -------------------------------------------------------------------------

  Widget _buildUserBubble() {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: BetaColors.card,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(4),
          ),
          border: Border.all(color: BetaColors.purple.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: BetaColors.purple.withValues(alpha: 0.13),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(message.text, style: BetaText.body),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // ASSISTANT CARD
  // -------------------------------------------------------------------------

  Widget _buildAssistantCard(BuildContext context, bool showTyping) {
    final Widget body;

    if (showTyping) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: TypingIndicator(),
      );
    } else {
      body = Text(
        message.text,
        style: BetaText.body.copyWith(color: BetaColors.textSecondary),
      );
    }

    final Widget card = Container(
      margin: const EdgeInsets.only(right: 32),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: BetaColors.backgroundSecondary,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: body,
    );

    if (message.status != ChatMessageStatus.complete || message.text.isEmpty) {
      return card;
    }

    // Long-press copies the finished reply.
    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: message.text));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: card,
    );
  }

  // -------------------------------------------------------------------------
  // META ROW (timestamp + mic marker + retry)
  // -------------------------------------------------------------------------

  Widget _buildMetaRow() {
    final List<Widget> items = [
      Text(_formatTime(message.time), style: BetaText.timestamp),
    ];

    if (message.viaVoice) {
      items.addAll([
        const SizedBox(width: 6),
        const Icon(
          Icons.mic_rounded,
          size: 12,
          color: BetaColors.textSecondary,
        ),
      ]);
    }

    if (message.status == ChatMessageStatus.error) {
      items.addAll([
        const SizedBox(width: 12),
        InkWell(
          onTap: onRetry,
          child: Text(
            'Retry',
            style: BetaText.timestamp.copyWith(
              color: BetaColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ]);
    }

    return Padding(
      padding: EdgeInsets.only(
        left: _isUser ? 0 : 4,
        right: _isUser ? 4 : 0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: items,
      ),
    );
  }
}
