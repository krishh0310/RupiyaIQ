import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';
import 'providers.dart';

Future<void> showBudgetSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const _BudgetSheet(),
    );

class _BudgetSheet extends ConsumerStatefulWidget {
  const _BudgetSheet();

  @override
  ConsumerState<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends ConsumerState<_BudgetSheet> {
  late final Map<String, TextEditingController> _controllers;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final budgets = ref.read(budgetsProvider).valueOrNull ?? const {};
    _controllers = {
      for (final c in kCategories)
        c.name: TextEditingController(text: budgets[c.name]?.toStringAsFixed(0) ?? ''),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(budgetsProvider.notifier).setAll({
        for (final e in _controllers.entries) e.key: parseAmount(e.value.text) ?? 0,
      });
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, "Couldn't save budgets", isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Monthly budgets', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Leave empty for no budget.', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            children: [
              for (final c in kCategories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    CategoryIcon(c.name, size: 36),
                    const SizedBox(width: 12),
                    Expanded(child: Text(c.name)),
                    SizedBox(
                      width: 130,
                      child: TextField(
                        controller: _controllers[c.name],
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        textAlign: TextAlign.end,
                        decoration: const InputDecoration(prefixText: '₹ ', hintText: '—', isDense: true),
                      ),
                    ),
                  ]),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Save budgets'),
            ),
          ),
        ),
      ]),
    );
  }
}
