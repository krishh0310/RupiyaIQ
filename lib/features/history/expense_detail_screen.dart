import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../dashboard/providers.dart';
import '../insights/insights_provider.dart';
import '../scan/review_screen.dart';
import 'history_screen.dart';

class ExpenseDetailScreen extends ConsumerWidget {
  const ExpenseDetailScreen({super.key, required this.expenseId});
  final int expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read live from the list so edits show up immediately.
    final e = ref.watch(expensesProvider).valueOrNull?.where((x) => x.id == expenseId).firstOrNull;
    if (e == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(emoji: '🗑️', title: 'This expense no longer exists'),
      );
    }
    final t = Theme.of(context).textTheme;
    final info = categoryInfo(e.category);
    final anomaly = ref.watch(anomaliesProvider).where((a) => a.expense.id == e.id).firstOrNull;

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 300,
          actions: [
            IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_rounded), onPressed: () => _edit(context, ref, e)),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () {
                Navigator.pop(context);
                deleteWithUndo(context, ref, e);
              },
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: GestureDetector(
              onTap: e.hasImage ? () => _openFullImage(context, e) : null,
              child: Hero(
                tag: receiptHeroTag(e.id!),
                child: e.hasImage
                    ? Image.file(File(e.imagePath!), fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _placeholder(info))
                    : _placeholder(info),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          sliver: SliverList.list(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.merchant, style: t.headlineSmall),
                  const SizedBox(height: 6),
                  Text(longDate(e.date), style: t.bodyMedium),
                ]),
              ),
              Text(formatInrExact(e.total), style: t.headlineSmall?.copyWith(color: info.color)),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              CategoryChip(e.category, dense: false),
              Chip(avatar: const Icon(Icons.payments_rounded, size: 16), label: Text(e.paymentMethod)),
              if (e.confidence > 0)
                Chip(
                  avatar: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: Text('AI ${(e.confidence * 100).round()}%'),
                ),
            ]),
            if (anomaly != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.danger, width: 1.5),
                  borderRadius: BorderRadius.circular(14),
                  color: AppColors.danger.withValues(alpha: 0.08),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
                  const SizedBox(width: 10),
                  Expanded(child: Text(anomaly.message, style: t.bodySmall)),
                ]),
              ),
            ],
            const SectionHeader('Breakdown'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  if (e.items.isEmpty)
                    Text('No itemised lines on this bill.', style: t.bodySmall)
                  else
                    for (final item in e.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(item.name, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                              if (item.quantity != 1)
                                Text('${_qty(item.quantity)} × ${formatInrExact(item.price)}', style: t.bodySmall),
                            ]),
                          ),
                          Text(formatInrExact(round2(item.lineTotal))),
                        ]),
                      ),
                  const Divider(height: 20),
                  _row(context, 'Subtotal', e.subtotal),
                  _row(context, 'Tax', e.tax),
                  const SizedBox(height: 4),
                  _row(context, 'Total', e.total, bold: true),
                ]),
              ),
            ),
            if ((e.rawOcr ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: ExpansionTile(
                  shape: const Border(),
                  leading: const Icon(Icons.text_snippet_outlined),
                  title: const Text('Scanned text (OCR)'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [SelectableText(e.rawOcr!, style: t.bodySmall?.copyWith(fontFamily: 'monospace'))],
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  static String _qty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);

  Widget _placeholder(CategoryInfo info) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [info.color.withValues(alpha: 0.9), info.color.withValues(alpha: 0.5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(child: Icon(info.icon, size: 96, color: Colors.white.withValues(alpha: 0.9))),
      );

  Widget _row(BuildContext context, String label, double v, {bool bold = false}) {
    final t = Theme.of(context).textTheme;
    final style = bold ? t.titleMedium : t.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [Text(label, style: style), const Spacer(), Text(formatInrExact(v), style: style)]),
    );
  }

  void _edit(BuildContext context, WidgetRef ref, Expense e) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (ctx) => ExpenseEditor(
        initial: e,
        title: 'Edit expense',
        submitLabel: 'Save changes',
        onSubmit: (updated) async {
          await ref.read(expensesProvider.notifier).updateExpense(updated);
          if (ctx.mounted) {
            Navigator.pop(ctx);
            showSnack(context, 'Expense updated');
          }
        },
      ),
    ));
  }

  void _openFullImage(BuildContext context, Expense e) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: Hero(tag: receiptHeroTag(e.id!), child: Image.file(File(e.imagePath!))),
          ),
        ),
      ),
    ));
  }
}
