import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/services/gemini_service.dart';
import '../dashboard/providers.dart';
import 'anomaly_engine.dart';
import 'chat_service.dart';
import 'insight_generator.dart';
import 'spending_summary.dart';

final insightPeriodProvider = StateProvider<InsightPeriod>((ref) => InsightPeriod.week);

/// AI insight cards, cached in memory for the session per period.
/// Regenerated when the regenerate button invalidates it, or when the number
/// of bills changes (a new scan / delete) — not on every rebuild.
/// InsightGenerator never throws: offline → local template cards from SQLite data.
final insightCardsProvider =
    FutureProvider.family<({List<InsightCard> cards, DateTime generatedAt}), InsightPeriod>((ref, period) async {
  ref.watch(expensesProvider.select((s) => s.valueOrNull?.length));
  final expenses = await ref.read(expensesProvider.future);
  final cards = await InsightGenerator(ref.read(geminiServiceProvider)).generate(expenses, period);
  return (cards: cards, generatedAt: DateTime.now());
});

final anomaliesProvider = Provider<List<Anomaly>>((ref) {
  final expenses = ref.watch(expensesProvider).valueOrNull ?? const [];
  return AnomalyDetectionEngine.detect(expenses);
});

class ChatMessage {
  const ChatMessage({required this.fromUser, required this.text, this.isError = false});
  final bool fromUser;
  final String text;
  final bool isError;
}

class ChatState {
  const ChatState({this.messages = const [], this.waiting = false, this.streaming = false});
  final List<ChatMessage> messages;

  /// True until the first chunk arrives → shows the typing indicator.
  final bool waiting;
  final bool streaming;
  bool get busy => waiting || streaming;
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);

class ChatNotifier extends Notifier<ChatState> {
  @override
  ChatState build() => const ChatState();

  Future<void> ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || state.busy) return;

    // Gemini requires strictly alternating user/model turns, so only keep
    // question→answer pairs whose answer succeeded.
    final history = <(bool, String)>[];
    final msgs = state.messages;
    for (var i = 0; i + 1 < msgs.length; i++) {
      if (msgs[i].fromUser && !msgs[i + 1].fromUser && !msgs[i + 1].isError) {
        history.addAll([(true, msgs[i].text), (false, msgs[i + 1].text)]);
      }
    }
    var messages = [...state.messages, ChatMessage(fromUser: true, text: q)];
    state = ChatState(messages: messages, waiting: true);

    var expenses = const <Expense>[];
    final buffer = StringBuffer();
    try {
      expenses = await ref.read(expensesProvider.future);
      await for (final chunk in ChatService(ref.read(geminiServiceProvider)).ask(q, expenses, history)) {
        buffer.write(chunk);
        state = ChatState(
          messages: [...messages, ChatMessage(fromUser: false, text: buffer.toString())],
          streaming: true,
        );
      }
      if (buffer.isEmpty) throw const GeminiException('Gemini returned an empty answer.');
      messages = [...messages, ChatMessage(fromUser: false, text: buffer.toString())];
      state = ChatState(messages: messages);
    } catch (_) {
      // Friendly, locally-computed answer (no API) instead of a raw error.
      state = ChatState(messages: [
        ...messages,
        if (buffer.isNotEmpty) ChatMessage(fromUser: false, text: buffer.toString()),
        ChatMessage(
          fromUser: false,
          text: ChatService.offlineAnswer(expenses),
          isError: true,
        ),
      ]);
    }
  }

  void clear() => state = const ChatState();
}
