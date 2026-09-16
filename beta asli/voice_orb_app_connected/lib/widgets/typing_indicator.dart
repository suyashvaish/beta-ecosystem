import 'package:flutter/material.dart';

/// Three dots that pulse in sequence, shown in place of an assistant
/// message's text while Beta is composing a reply and no text has
/// streamed in yet.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 14,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (i) {
              // Stagger each dot's phase by a third of the cycle so they
              // pulse one after another rather than all together.
              final phase = (_controller.value + (i * 0.33)) % 1.0;
              final triangle = 1.0 - (2 * phase - 1.0).abs();
              final opacity = (0.3 + 0.7 * triangle).clamp(0.3, 1.0);
              return Opacity(opacity: opacity, child: const _Dot());
            }),
          );
        },
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        color: Colors.white70,
        shape: BoxShape.circle,
      ),
    );
  }
}
