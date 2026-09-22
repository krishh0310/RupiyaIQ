import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../data/models.dart';
import 'constants.dart';
import 'theme.dart';
import 'utils.dart';

/// Press feedback: scales child to 0.95 while a finger is down. Uses a raw
/// Listener so it works around buttons without fighting their gestures.
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.95});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    Widget child = AnimatedScale(
      scale: _down ? widget.scale : 1,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: widget.child,
    );
    if (widget.onTap != null || widget.onLongPress != null) {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: child,
      );
    }
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: child,
    );
  }
}

/// Fade + slide-up entrance, staggered 50 ms per [index].
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(Duration(milliseconds: 50 * min(widget.index, 12)), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _curve,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(_curve),
          child: widget.child,
        ),
      );
}

/// Moving highlight over skeleton boxes.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF2A2A2A) : const Color(0xFFE6E8EF);
    final highlight = dark ? const Color(0xFF3D3D3D) : const Color(0xFFF7F8FB);
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          colors: [base, highlight, base],
          stops: const [0.35, 0.5, 0.65],
          transform: _SlideGradient(_c.value),
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.t);
  final double t;
  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (2 * t - 1), 0, 0);
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(radius)),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.emoji, required this.title, this.subtitle, this.action});
  final String emoji;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Text(emoji, style: const TextStyle(fontSize: 64)),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: t.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: t.bodySmall?.color)),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: EmptyState(
          emoji: '😕',
          title: message,
          action: OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
        ),
      );
}

class CategoryIcon extends StatelessWidget {
  const CategoryIcon(this.category, {super.key, this.size = 40});
  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final info = categoryInfo(category);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: info.color.withValues(alpha: 0.15), shape: BoxShape.circle),
      child: Icon(info.icon, color: info.color, size: size * 0.5),
    );
  }
}

class CategoryChip extends StatelessWidget {
  const CategoryChip(this.category, {super.key, this.dense = true});
  final String category;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final info = categoryInfo(category);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 12, vertical: dense ? 2 : 6),
      decoration: BoxDecoration(
        color: info.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(info.icon, size: dense ? 12 : 16, color: info.color),
        const SizedBox(width: 4),
        Text(
          info.name,
          style: TextStyle(color: info.color, fontSize: dense ? 11 : 13, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

/// 4:3 rounded receipt thumbnail (category-coloured placeholder when there is
/// no photo, e.g. demo data). Wrapped in a Hero for the detail transition.
class ReceiptThumb extends StatelessWidget {
  const ReceiptThumb({super.key, required this.expense, this.width = 64, this.radius = 12, this.hero = true});
  final Expense expense;
  final double width;
  final double radius;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final info = categoryInfo(expense.category);
    final placeholder = Container(
      color: info.color.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Icon(info.icon, color: info.color, size: width * 0.4),
    );
    final thumb = SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: expense.hasImage
              ? Image.file(
                  File(expense.imagePath!),
                  fit: BoxFit.cover,
                  cacheWidth: (width * 3).round(),
                  errorBuilder: (_, _, _) => placeholder,
                )
              : placeholder,
        ),
      ),
    );
    return hero && expense.id != null ? Hero(tag: receiptHeroTag(expense.id!), child: thumb) : thumb;
  }
}

String receiptHeroTag(int id) => 'receipt-$id';

class ExpenseTile extends StatelessWidget {
  const ExpenseTile({super.key, required this.expense, this.onTap});
  final Expense expense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return PressableScale(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            ReceiptThumb(expense: expense),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(expense.merchant, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Row(children: [
                  CategoryChip(expense.category),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(shortDate(expense.date), maxLines: 1, style: t.bodySmall),
                  ),
                ]),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatInrExact(expense.total), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              if (expense.isAnomaly) ...[
                const SizedBox(height: 4),
                const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.danger),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          ?trailing,
        ]),
      );
}

void showSnack(BuildContext context, String message, {bool isError = false, SnackBarAction? action}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? AppColors.danger : null,
      action: action,
      duration: Duration(seconds: action != null ? 5 : 3),
    ));
}
