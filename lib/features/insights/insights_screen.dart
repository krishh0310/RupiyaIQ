import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../dashboard/providers.dart';
import 'charts.dart';
import 'chat_widget.dart';
import 'insight_generator.dart';
import 'insights_provider.dart';
import 'spending_summary.dart';

class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ref.watch(expensesProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => ErrorRetry(
              message: "Couldn't load insights",
              onRetry: () => ref.read(expensesProvider.notifier).refresh(),
            ),
            data: _body,
          ),
    );
  }

  Widget _body(List<Expense> expenses) {
    final t = Theme.of(context).textTheme;
    final period = ref.watch(insightPeriodProvider);
    final now = DateTime.now();
    final summary = SpendingSummary(expenses, period, now: now);
    final change = pctChange(summary.total, summary.previousTotal);
    final anomalies = ref.watch(anomaliesProvider);

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        Text('Insights', style: t.headlineSmall),
        const SizedBox(height: 12),
        SegmentedButton<InsightPeriod>(
          segments: const [
            ButtonSegment(value: InsightPeriod.week, label: Text('Week'), icon: Icon(Icons.view_week_rounded)),
            ButtonSegment(value: InsightPeriod.month, label: Text('Month'), icon: Icon(Icons.calendar_month_rounded)),
          ],
          selected: {period},
          onSelectionChanged: (s) => ref.read(insightPeriodProvider.notifier).state = s.first,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(period == InsightPeriod.week ? 'Last 7 days' : 'This month', style: t.bodySmall),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: summary.total),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => Text(formatInr(v), style: t.headlineSmall),
                  ),
                ]),
              ),
              if (change != null)
                Chip(
                  backgroundColor: (change > 0 ? AppColors.danger : AppColors.success).withValues(alpha: 0.12),
                  avatar: Icon(change > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                      color: change > 0 ? AppColors.danger : AppColors.success, size: 18),
                  label: Text('${change.abs().toStringAsFixed(0)}% vs last ${period.label}'),
                ),
            ]),
          ),
        ),

        const SectionHeader('Where it went'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: summary.byCategory.isEmpty
                ? Text('No spending this ${period.label} yet.', style: t.bodyMedium)
                : CategoryDonut(key: ValueKey(period), totals: summary.byCategory),
          ),
        ),

        SectionHeader(period == InsightPeriod.week ? 'Daily spend' : 'Weekly spend'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
            child: SpendBarChart(buckets: spendBuckets(expenses, period, now)),
          ),
        ),

        SectionHeader(
          'AI insights',
          trailing: IconButton(
            tooltip: 'Regenerate',
            onPressed: () => ref.invalidate(insightCardsProvider(period)),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        _InsightCards(period: period),

        if (anomalies.isNotEmpty) ...[
          const SectionHeader('⚠️ Anomaly alerts'),
          for (final (i, a) in anomalies.take(5).indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FadeSlideIn(
                index: i,
                child: PressableScale(
                  onTap: () => openExpenseDetail(context, a.expense.id!),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardTheme.color,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.danger, width: 1.5),
                    ),
                    child: Row(children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a.expense.merchant, style: t.titleSmall),
                          const SizedBox(height: 2),
                          Text(a.message, style: t.bodySmall),
                        ]),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ]),
                  ),
                ),
              ),
            ),
        ],

        const SectionHeader('Ask your money'),
        AskYourMoney(onNewMessage: _scrollToBottom),
      ],
    );
  }
}

class _InsightCards extends ConsumerWidget {
  const _InsightCards({required this.period});
  final InsightPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return ref.watch(insightCardsProvider(period)).when(
          loading: () => Shimmer(
            child: Column(children: [
              for (var i = 0; i < 2; i++)
                const Padding(padding: EdgeInsets.only(bottom: 10), child: SkeletonBox(height: 84, radius: 18)),
            ]),
          ),
          error: (_, _) => const SizedBox.shrink(), // generator never throws; defensive only
          data: (result) {
            final cards = result.cards;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (i, c) in cards.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FadeSlideIn(index: i, child: _InsightTile(card: c)),
              ),
            Row(children: [
              Icon(
                cards.isNotEmpty && cards.first.fromAi ? Icons.auto_awesome_rounded : Icons.cloud_off_rounded,
                size: 14,
                color: t.bodySmall?.color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Last updated: ${DateFormat('h:mm:ss a').format(result.generatedAt)}'
                  '${cards.isNotEmpty && cards.first.fromAi ? ' · Gemini $geminiModel' : hasGeminiKey ? ' · offline — tap ↻ to retry' : ' · offline (no API key)'}',
                  style: t.bodySmall,
                ),
              ),
            ]),
          ]);
          },
        );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({required this.card});
  final InsightCard card;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [AppColors.primary.withValues(alpha: 0.12), AppColors.accent.withValues(alpha: 0.10)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(card.emoji, style: const TextStyle(fontSize: 28)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(card.title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
              if (card.fromAi) const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.primary),
            ]),
            const SizedBox(height: 4),
            Text(card.message, style: t.bodyMedium?.copyWith(height: 1.35)),
          ]),
        ),
      ]),
    );
  }
}
