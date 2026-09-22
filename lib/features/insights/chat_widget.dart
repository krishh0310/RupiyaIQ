import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'insights_provider.dart';

/// "Ask your money" — chat bubbles, typing indicator, text + voice input.
class AskYourMoney extends ConsumerStatefulWidget {
  const AskYourMoney({super.key, required this.onNewMessage});

  /// Lets the parent page scroll to the bottom as answers stream in.
  final VoidCallback onNewMessage;

  @override
  ConsumerState<AskYourMoney> createState() => _AskYourMoneyState();
}

class _AskYourMoneyState extends ConsumerState<AskYourMoney> {
  static const _suggestions = [
    'How much did I spend on food this month?',
    "What's my biggest expense category?",
    'Where can I cut back?',
  ];

  final _input = TextEditingController();
  final _speech = SpeechToText();
  bool _listening = false;

  @override
  void dispose() {
    _speech.cancel();
    _input.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final q = (text ?? _input.text).trim();
    if (q.isEmpty) return;
    _input.clear();
    FocusScope.of(context).unfocus();
    ref.read(chatProvider.notifier).ask(q);
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      try {
        await _speech.stop();
      } catch (_) {}
      if (mounted) setState(() => _listening = false);
      return;
    }
    try {
      // initialize() asks for the microphone permission the first time.
      final ok = await _speech.initialize(
        onStatus: (s) {
          if ((s == 'done' || s == 'notListening') && mounted) setState(() => _listening = false);
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (!ok) {
        if (mounted) showSnack(context, 'Voice input unavailable — check microphone permission.', isError: true);
        return;
      }
      setState(() => _listening = true);
      await _speech.listen(
        listenOptions: SpeechListenOptions(localeId: null, partialResults: true),
        onResult: (r) {
          _input.text = r.recognizedWords;
          if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
            setState(() => _listening = false);
            _send(r.recognizedWords);
          }
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _listening = false);
        showSnack(context, 'Voice input unavailable on this device.', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chatProvider, (_, _) => widget.onNewMessage());
    final chat = ref.watch(chatProvider);
    final t = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('💬', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Expanded(child: Text('Ask your money', style: t.titleMedium)),
            if (chat.messages.isNotEmpty)
              IconButton(
                tooltip: 'Clear chat',
                onPressed: chat.busy ? null : () => ref.read(chatProvider.notifier).clear(),
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
          ]),
          const SizedBox(height: 8),
          if (chat.messages.isEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in _suggestions)
                ActionChip(label: Text(s, style: t.bodySmall), onPressed: () => _send(s)),
            ]),
          for (final m in chat.messages) _Bubble(message: m),
          if (chat.waiting) const _TypingIndicator(),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                enabled: !chat.busy,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: _listening ? 'Listening…' : 'Ask about your spending',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: 'Speak',
              onPressed: chat.busy ? null : _toggleMic,
              style: _listening ? IconButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white) : null,
              icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
            ),
            IconButton.filled(
              tooltip: 'Send',
              onPressed: chat.busy ? null : _send,
              icon: const Icon(Icons.send_rounded),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.fromUser;
    final bg = isUser
        ? AppColors.primary
        : message.isError
            ? AppColors.warning.withValues(alpha: 0.15)
            : scheme.surfaceContainerHighest;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
        ),
        child: Text(message.text, style: TextStyle(color: isUser ? Colors.white : scheme.onSurface, height: 1.35)),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < 3; i++)
                Transform.translate(
                  // Each dot bounces a third of a cycle after the previous one.
                  offset: Offset(0, -4 * (1 - ((_c.value * 3 - i) % 3 - 0.5).abs() * 2).clamp(0.0, 1.0)),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle),
                  ),
                ),
            ]),
          ),
        ),
      );
}
