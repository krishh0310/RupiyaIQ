import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/services/gemini_service.dart';
import 'spending_summary.dart';

/// "Ask your money": answers questions grounded ONLY in the user's own data.
class ChatService {
  ChatService(this._gemini);
  final GeminiService _gemini;

  /// Streams the answer chunk by chunk. [history] = previous (isUser, text) turns.
  Stream<String> ask(String question, List<Expense> expenses, List<(bool, String)> history) =>
      _gemini.chatStream(system: buildSystemPrompt(expenses), history: history, message: question);

  /// The grounding context injected as the system instruction:
  ///   • rules (use only this data, be brief, ₹ formatting),
  ///   • month + week summaries (category totals, % change, top merchants),
  ///   • the 15 most recent bills and any large (>₹1,000) bills in 60 days.
  /// Kept compact (~1–2 KB) so answers stay fast on a phone connection.
  static String buildSystemPrompt(List<Expense> expenses, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final month = SpendingSummary(expenses, InsightPeriod.month, now: today);
    final week = SpendingSummary(expenses, InsightPeriod.week, now: today);
    final sixtyDaysAgo = today.subtract(const Duration(days: 60));
    String line(Expense e) =>
        '${isoDate(e.date)} | ${e.merchant} | ${e.category} | ${formatInrExact(e.total)} | ${e.paymentMethod}';
    final large = expenses.where((e) => e.total > 1000 && e.date.isAfter(sixtyDaysAgo)).take(15);

    return '''
You are RupiyaIQ, a concise personal-finance assistant inside an Indian expense-tracking app.
Answer using ONLY the expense data below. If the data can't answer the question, say so briefly — never guess or invent numbers.
Keep answers under 80 words, use ₹ with Indian grouping (₹12,340), and plain text (no markdown tables).
Today is ${isoDate(today)}. Total bills on record: ${expenses.length}.

== THIS MONTH ==
${month.toPromptText()}

== THIS WEEK ==
${week.toPromptText()}

== 15 MOST RECENT BILLS (date | merchant | category | total | payment) ==
${expenses.take(15).map(line).join('\n')}

== LARGE BILLS (> ₹1,000, last 60 days) ==
${large.map(line).join('\n')}''';
  }

  /// Offline fallback answer, built locally from the DB — the chat is never a dead end.
  static String offlineAnswer(List<Expense> expenses) {
    final month = SpendingSummary(expenses, InsightPeriod.month);
    if (month.byCategory.isEmpty) {
      return "AI needs internet for questions — and there are no bills this month yet. Scan one to get started!";
    }
    final top = month.byCategory.entries.first;
    return "AI needs internet for questions — but here's your top category this month: "
        '${top.key} (${formatInr(top.value)})';
  }
}
