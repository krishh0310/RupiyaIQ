import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/services/gemini_service.dart';
import 'spending_summary.dart';

class InsightCard {
  const InsightCard({required this.emoji, required this.title, required this.message, this.fromAi = false});
  final String emoji;
  final String title;
  final String message;
  final bool fromAi;
}

/// expenses → compact summary → Gemini → 2–3 plain-language cards.
/// Falls back to locally templated cards when offline / no key / bad JSON.
class InsightGenerator {
  InsightGenerator(this._gemini);
  final GeminiService _gemini;

  static const _system =
      'You are a friendly personal-finance coach for an Indian user. You only use the data given. '
      'You never invent numbers.';

  Future<List<InsightCard>> generate(List<Expense> all, InsightPeriod period, {DateTime? now}) async {
    final summary = SpendingSummary(all, period, now: now);
    if (summary.isEmpty) {
      return const [
        InsightCard(
          emoji: '🧾',
          title: 'No data yet',
          message: 'Scan a few bills and your personalised insights will appear here.',
        ),
      ];
    }
    try {
      final raw = await _gemini.generate(_prompt(summary), system: _system, json: true);
      final decoded = GeminiService.decodeJsonLoose(raw);
      final list = decoded is Map ? decoded['insights'] : decoded;
      if (list is List) {
        final cards = [
          for (final c in list.whereType<Map>())
            if ('${c['message'] ?? ''}'.trim().isNotEmpty)
              InsightCard(
                emoji: '${c['emoji'] ?? '💡'}',
                title: '${c['title'] ?? 'Insight'}',
                message: '${c['message']}',
                fromAi: true,
              ),
        ];
        if (cards.isNotEmpty) return cards.take(3).toList();
      }
    } on GeminiException {
      // fall through to local insights
    } catch (_) {}
    return localInsights(summary);
  }

  /// Prompt = task + output format + the compact data block.
  String _prompt(SpendingSummary s) => '''
Write 2 or 3 short insight cards about this user's spending this ${s.period.label}.
Each card must mention concrete rupee amounts and, where useful, % change vs the previous ${s.period.label} and the merchant driving it.
Tone: warm, plain language, like "🍔 You spent ₹2,340 on Food this week — 32% above last week. Zomato orders made up most of it." Praise savings, flag overspending.
Use Indian number formatting with ₹ (e.g. ₹12,340).
Return ONLY a JSON array: [{"emoji": "one emoji", "title": "max 5 words", "message": "max 30 words"}]

DATA:
${s.toPromptText()}''';

  /// Offline template insights — always available.
  static List<InsightCard> localInsights(SpendingSummary s) {
    final cards = <InsightCard>[];
    if (s.byCategory.isNotEmpty) {
      final top = s.byCategory.entries.first;
      final share = s.total > 0 ? top.value / s.total * 100 : 0;
      cards.add(InsightCard(
        emoji: categoryInfo(top.key).emoji,
        title: 'Top category',
        message: 'Top category this ${s.period.label}: ${top.key} at ${formatInr(top.value)} '
            '(${share.toStringAsFixed(0)}% of your spending).',
      ));
    }
    final change = pctChange(s.total, s.previousTotal);
    if (change != null) {
      final up = change >= 0;
      cards.add(InsightCard(
        emoji: up ? '📈' : '📉',
        title: up ? 'Spending is up' : 'Spending is down',
        message: 'You spent ${formatInr(s.total)} this ${s.period.label} — '
            '${change.abs().toStringAsFixed(0)}% ${up ? 'more' : 'less'} than the previous ${s.period.label} '
            '(${formatInr(s.previousTotal)}).${up ? '' : ' Nice!'}',
      ));
    }
    if (s.largest.isNotEmpty) {
      final big = s.largest.first;
      cards.add(InsightCard(
        emoji: '💸',
        title: 'Biggest bill',
        message: 'Your biggest bill was ${formatInr(big.total)} at ${big.merchant} on ${shortDate(big.date)} (${big.category}).',
      ));
    }
    if (cards.isEmpty) {
      cards.add(InsightCard(
        emoji: '🌱',
        title: 'Quiet ${s.period.label}',
        message: 'No bills this ${s.period.label} yet. Last ${s.period.label} you spent ${formatInr(s.previousTotal)}.',
      ));
    }
    return cards;
  }
}
