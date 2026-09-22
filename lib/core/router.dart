import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/dashboard/home_screen.dart';
import '../features/history/expense_detail_screen.dart';
import '../features/history/history_screen.dart';
import '../features/insights/insights_screen.dart';
import '../features/scan/scan_flow_screen.dart';
import '../features/scan/scan_provider.dart';

/// Bottom-nav tabs. Scan is a tab too, but it opens full-screen (camera needs
/// the whole screen) instead of swapping the body.
enum AppTab { home, scan, insights, history }

final tabProvider = StateProvider<AppTab>((ref) => AppTab.home);

void openScanFlow(BuildContext context, WidgetRef ref) {
  ref.read(scanProvider.notifier).reset();
  Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => const ScanFlowScreen(),
  ));
}

void openExpenseDetail(BuildContext context, int expenseId) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ExpenseDetailScreen(expenseId: expenseId),
  ));
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabProvider);
    final body = switch (tab) {
      AppTab.insights => const InsightsScreen(),
      AppTab.history => const HistoryScreen(),
      _ => const HomeScreen(),
    };

    return Scaffold(
      extendBody: true,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOut,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(anim),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(tab), child: body),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _ScanFab(onPressed: () => openScanFlow(context, ref)),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          _NavItem(icon: Icons.home_rounded, label: 'Home', selected: tab == AppTab.home,
              onTap: () => ref.read(tabProvider.notifier).state = AppTab.home),
          _NavItem(icon: Icons.document_scanner_rounded, label: 'Scan', selected: false,
              onTap: () => openScanFlow(context, ref)),
          const SizedBox(width: 72),
          _NavItem(icon: Icons.insights_rounded, label: 'Insights', selected: tab == AppTab.insights,
              onTap: () => ref.read(tabProvider.notifier).state = AppTab.insights),
          _NavItem(icon: Icons.history_rounded, label: 'History', selected: tab == AppTab.history,
              onTap: () => ref.read(tabProvider.notifier).state = AppTab.history),
        ]),
      ),
    );
  }
}

class _ScanFab extends StatefulWidget {
  const _ScanFab({required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<_ScanFab> createState() => _ScanFabState();
}

class _ScanFabState extends State<_ScanFab> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => setState(() => _down = true),
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: AnimatedScale(
          scale: _down ? 0.95 : 1,
          duration: const Duration(milliseconds: 110),
          child: SizedBox(
            width: 68,
            height: 68,
            child: FloatingActionButton(
              heroTag: 'scan-fab',
              onPressed: widget.onPressed,
              shape: const CircleBorder(),
              elevation: 6,
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              tooltip: 'Scan a bill',
              child: const Icon(Icons.camera_alt_rounded, size: 30),
            ),
          ),
        ),
      );
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedScale(
            scale: selected ? 1.15 : 1,
            duration: const Duration(milliseconds: 200),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    );
  }
}
