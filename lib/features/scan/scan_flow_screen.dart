import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../dashboard/providers.dart';
import 'camera_screen.dart';
import 'review_screen.dart';
import 'scan_provider.dart';

/// Hosts the 4-step scan flow: camera → processing → review → success.
class ScanFlowScreen extends ConsumerWidget {
  const ScanFlowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Surface fallbacks ("AI timed out…") as a snackbar once, when they appear.
    ref.listen<ScanState>(scanProvider, (prev, next) {
      if (next.notice != null && next.notice != prev?.notice) {
        showSnack(context, next.notice!, isError: true);
      }
    });
    final state = ref.watch(scanProvider);

    final child = switch (state.stage) {
      ScanStage.capture => const CameraView(key: ValueKey('capture')),
      ScanStage.processing => _ProcessingView(key: const ValueKey('processing'), state: state),
      ScanStage.review => ExpenseEditor(
          key: ValueKey(state.draft),
          initial: state.draft!,
          onSubmit: (e) => _save(context, ref, e),
        ),
      ScanStage.success => _SuccessView(key: const ValueKey('success'), expense: state.saved!),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(a), child: c),
      ),
      child: child,
    );
  }

  /// Duplicate check, then save. Keeps the user in review on "Cancel".
  Future<void> _save(BuildContext context, WidgetRef ref, Expense e) async {
    final dup = await ref.read(repositoryProvider).findDuplicate(e);
    if (dup != null) {
      if (!context.mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.content_copy_rounded, color: AppColors.warning),
          title: const Text('This looks like a bill you already added'),
          content: Text('${dup.merchant} · ${formatInrExact(dup.total)} · ${longDate(dup.date)}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'view'), child: const Text('View')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(ctx, 'add'),
              child: const Text('Add anyway'),
            ),
          ],
        ),
      );
      if (choice == 'view' && context.mounted) {
        openExpenseDetail(context, dup.id!);
        return;
      }
      if (choice != 'add') return;
    }
    final id = await ref.read(expensesProvider.notifier).add(e);
    ref.read(scanProvider.notifier).markSaved(e.copyWith(id: id));
  }
}

/// Step 2: photo with a sweeping scan line, skeleton of the bill, cycling stage text.
class _ProcessingView extends StatelessWidget {
  const _ProcessingView({super.key, required this.state});
  final ScanState state;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Spacer(),
            if (state.sourcePath != null)
              SizedBox(
                width: 220,
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(fit: StackFit.expand, children: [
                      Image.file(File(state.sourcePath!), fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12)),
                      const _ScanLine(),
                    ]),
                  ),
                ),
              ),
            const SizedBox(height: 28),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a), child: c),
              ),
              child: Text(kProcessingSteps[state.step], key: ValueKey(state.step), style: t.titleLarge),
            ),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < kProcessingSteps.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == state.step ? 28 : 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: i <= state.step ? AppColors.primary : Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
            ]),
            const SizedBox(height: 28),
            // Skeleton of the bill that's being built.
            Shimmer(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SkeletonBox(width: 180, height: 18),
                const SizedBox(height: 12),
                for (final w in [260.0, 220.0, 240.0])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(children: [
                      SkeletonBox(width: w * 0.6),
                      const Spacer(),
                      const SkeletonBox(width: 60),
                    ]),
                  ),
                const SizedBox(height: 4),
                const Row(children: [SkeletonBox(width: 90, height: 20), Spacer(), SkeletonBox(width: 90, height: 20)]),
              ]),
            ),
            const Spacer(),
          ]),
        ),
      ),
    );
  }
}

class _ScanLine extends StatefulWidget {
  const _ScanLine();

  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Align(
          alignment: Alignment(0, _c.value * 2 - 1),
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              color: AppColors.accent,
              boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.8), blurRadius: 16, spreadRadius: 2)],
            ),
          ),
        ),
      );
}

/// Step 4: animated checkmark + summary + next actions.
class _SuccessView extends ConsumerWidget {
  const _SuccessView({super.key, required this.expense});
  final Expense expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    // Re-read from the list so the anomaly flag computed after saving shows up.
    final saved = ref.watch(expensesProvider).valueOrNull?.where((e) => e.id == expense.id).firstOrNull ?? expense;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Spacer(),
            const _AnimatedCheck(),
            const SizedBox(height: 20),
            Text('Expense saved!', style: t.headlineSmall),
            const SizedBox(height: 24),
            FadeSlideIn(
              index: 4,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Row(children: [
                      ReceiptThumb(expense: saved, width: 72, hero: false),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(saved.merchant, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 6),
                          Row(children: [
                            CategoryChip(saved.category),
                            const SizedBox(width: 8),
                            Text(shortDate(saved.date), style: t.bodySmall),
                          ]),
                        ]),
                      ),
                      Text(formatInrExact(saved.total), style: t.titleLarge),
                    ]),
                    if (saved.items.isNotEmpty) ...[
                      const Divider(height: 24),
                      Text('${saved.items.length} items · paid via ${saved.paymentMethod}', style: t.bodySmall),
                    ],
                    if (saved.isAnomaly) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(children: [
                          const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
                          const SizedBox(width: 8),
                          Expanded(child: Text('This is unusually high for ${saved.category}. See Insights.', style: t.bodySmall)),
                        ]),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => ref.read(scanProvider.notifier).reset(),
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('Scan another'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () {
                ref.read(tabProvider.notifier).state = AppTab.home;
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
              child: const Text('View dashboard'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Custom-painted checkmark: circle sweeps in, then the tick draws itself.
class _AnimatedCheck extends StatefulWidget {
  const _AnimatedCheck();

  @override
  State<_AnimatedCheck> createState() => _AnimatedCheckState();
}

class _AnimatedCheckState extends State<_AnimatedCheck> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Transform.scale(
          scale: Curves.elasticOut.transform(min(1, _c.value * 1.4)).clamp(0.0, 1.2),
          child: CustomPaint(size: const Size(120, 120), painter: _CheckPainter(_c.value)),
        ),
      );
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    final circleT = Curves.easeOut.transform((t / 0.5).clamp(0.0, 1.0));
    final tickT = Curves.easeOut.transform(((t - 0.45) / 0.55).clamp(0.0, 1.0));

    canvas.drawCircle(center, r, Paint()..color = AppColors.success.withValues(alpha: 0.15 * circleT));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r - 4),
      -pi / 2,
      2 * pi * circleT,
      false,
      Paint()
        ..color = AppColors.success
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );

    if (tickT > 0) {
      final path = Path()
        ..moveTo(size.width * 0.30, size.height * 0.52)
        ..lineTo(size.width * 0.45, size.height * 0.66)
        ..lineTo(size.width * 0.72, size.height * 0.38);
      final metric = path.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * tickT),
        Paint()
          ..color = AppColors.success
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t;
}
