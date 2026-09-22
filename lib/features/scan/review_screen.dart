import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';

/// Step 3 of the scan flow (and the "Edit" screen from expense detail):
/// every AI-extracted field is editable, items can be added/removed.
class ExpenseEditor extends StatefulWidget {
  const ExpenseEditor({
    super.key,
    required this.initial,
    required this.onSubmit,
    this.title = 'Review expense',
    this.submitLabel = 'Save Expense',
  });

  final Expense initial;
  final Future<void> Function(Expense expense) onSubmit;
  final String title;
  final String submitLabel;

  @override
  State<ExpenseEditor> createState() => _ExpenseEditorState();
}

String _fmtNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

class _ItemRow {
  _ItemRow([ExpenseItem? item])
      : name = TextEditingController(text: item?.name ?? ''),
        price = TextEditingController(text: item == null ? '' : _fmtNum(item.price)),
        qty = TextEditingController(text: item == null ? '1' : _fmtNum(item.quantity));

  final TextEditingController name, price, qty;
  final key = UniqueKey();

  ExpenseItem? toItem() {
    final n = name.text.trim();
    if (n.isEmpty) return null;
    final q = parseAmount(qty.text) ?? 1;
    return ExpenseItem(name: n, price: parseAmount(price.text) ?? 0, quantity: q <= 0 ? 1 : q);
  }

  void dispose() {
    name.dispose();
    price.dispose();
    qty.dispose();
  }
}

class _ExpenseEditorState extends State<ExpenseEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _merchant, _subtotal, _tax, _total;
  late DateTime _date;
  late String _category;
  late String _payment;
  late final List<_ItemRow> _items;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _merchant = TextEditingController(text: e.merchant);
    _subtotal = TextEditingController(text: e.subtotal == 0 ? '' : _fmtNum(e.subtotal));
    _tax = TextEditingController(text: e.tax == 0 ? '' : _fmtNum(e.tax));
    _total = TextEditingController(text: e.total == 0 ? '' : _fmtNum(e.total));
    _date = e.date;
    _category = categoryInfo(e.category).name;
    _payment = kPaymentMethods.contains(e.paymentMethod) ? e.paymentMethod : 'Unknown';
    _items = [for (final i in e.items) _ItemRow(i)];
  }

  @override
  void dispose() {
    for (final c in [_merchant, _subtotal, _tax, _total]) {
      c.dispose();
    }
    for (final r in _items) {
      r.dispose();
    }
    super.dispose();
  }

  double get _itemsSum => _items.fold(0.0, (s, r) => s + (r.toItem()?.lineTotal ?? 0));

  Future<void> _pickDate() async {
    final last = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(last) ? last : _date,
      firstDate: DateTime(2000),
      lastDate: last,
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _removeItem(_ItemRow row) {
    setState(() => _items.remove(row));
    row.dispose();
  }

  void _useItemsSumAsTotal() {
    final sum = round2(_itemsSum);
    final tax = parseAmount(_tax.text) ?? 0;
    setState(() {
      _subtotal.text = _fmtNum(sum);
      _total.text = _fmtNum(round2(sum + tax));
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final total = parseAmount(_total.text) ?? 0;
    final tax = parseAmount(_tax.text) ?? 0;
    final subtotal = parseAmount(_subtotal.text) ?? (total - tax);
    final expense = widget.initial.copyWith(
      merchant: _merchant.text.trim(),
      date: dayOnly(_date),
      category: _category,
      paymentMethod: _payment,
      subtotal: round2(subtotal),
      tax: round2(tax),
      total: round2(total),
      items: [for (final r in _items) ?r.toItem()],
    );
    setState(() => _saving = true);
    try {
      await widget.onSubmit(expense);
    } catch (_) {
      if (mounted) showSnack(context, "Couldn't save this expense — please try again.", isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final info = categoryInfo(_category);
    final e = widget.initial;
    final lowConfidence = e.confidence < 0.6;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (e.hasImage)
              Center(
                child: SizedBox(
                  width: 200,
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(File(e.imagePath!), fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12)),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            _ConfidenceBanner(confidence: e.confidence, isEdit: e.id != null),
            const SizedBox(height: 12),

            // Category-tinted card with the key fields.
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: info.color.withValues(alpha: 0.6), width: 1.5),
              ),
              child: Column(children: [
                TextFormField(
                  controller: _merchant,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Merchant',
                    prefixIcon: Icon(Icons.storefront_rounded, color: info.color),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the shop name' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(info.icon, color: info.color),
                  ),
                  items: [
                    for (final c in kCategories)
                      DropdownMenuItem(
                        value: c.name,
                        child: Row(children: [
                          Container(width: 12, height: 12, decoration: BoxDecoration(color: c.color, shape: BoxShape.circle)),
                          const SizedBox(width: 10),
                          Text(c.name),
                        ]),
                      ),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? _category),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Date', prefixIcon: Icon(Icons.event_rounded)),
                        child: Text(shortDate(_date) + (_date.year != DateTime.now().year ? ' ${_date.year}' : '')),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _payment,
                      decoration: const InputDecoration(labelText: 'Paid via'),
                      items: [for (final m in kPaymentMethods) DropdownMenuItem(value: m, child: Text(m))],
                      onChanged: (v) => setState(() => _payment = v ?? _payment),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _amountField(_subtotal, 'Subtotal')),
                  const SizedBox(width: 8),
                  Expanded(child: _amountField(_tax, 'Tax')),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _total,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  style: t.titleLarge,
                  decoration: InputDecoration(
                    labelText: 'Total',
                    prefixText: '₹ ',
                    filled: true,
                    fillColor: lowConfidence ? AppColors.warning.withValues(alpha: 0.12) : null,
                  ),
                  validator: (v) => (parseAmount(v ?? '') ?? 0) <= 0 ? 'Enter the bill total' : null,
                ),
              ]),
            ),

            SectionHeader(
              'Items (${_items.length})',
              trailing: TextButton.icon(
                onPressed: () => setState(() => _items.add(_ItemRow())),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add item'),
              ),
            ),
            if (_items.isEmpty)
              Text('No items — that’s fine, the total is what counts.', style: t.bodySmall)
            else
              for (final row in _items)
                Padding(
                  key: row.key,
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      flex: 5,
                      child: TextField(
                        controller: row.name,
                        decoration: const InputDecoration(hintText: 'Item', isDense: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: row.qty,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(hintText: 'Qty', isDense: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: row.price,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(hintText: 'Price', prefixText: '₹', isDense: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove item',
                      onPressed: () => _removeItem(row),
                      icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.danger),
                    ),
                  ]),
                ),
            if (_items.isNotEmpty)
              Row(children: [
                Text('Items sum: ${formatInrExact(round2(_itemsSum))}', style: t.bodySmall),
                const Spacer(),
                TextButton(onPressed: _useItemsSumAsTotal, child: const Text('Use as total')),
              ]),

            if ((e.rawOcr ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
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
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: PressableScale(
            child: FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.check_rounded),
              label: Text(widget.submitLabel),
            ),
          ),
        ),
      ),
    );
  }

  Widget _amountField(TextEditingController c, String label) => TextFormField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: InputDecoration(labelText: label, prefixText: '₹ ', isDense: true),
      );
}

class _ConfidenceBanner extends StatelessWidget {
  const _ConfidenceBanner({required this.confidence, required this.isEdit});
  final double confidence;
  final bool isEdit;

  @override
  Widget build(BuildContext context) {
    if (isEdit) return const SizedBox.shrink();
    final (color, icon, text) = confidence == 0
        ? (AppColors.warning, Icons.edit_note_rounded, 'Manual entry — we pre-filled what we could read. Please check.')
        : confidence < 0.6
            ? (AppColors.warning, Icons.help_outline_rounded,
                'AI is ${(confidence * 100).round()}% sure — please double-check the total.')
            : (AppColors.success, Icons.auto_awesome_rounded,
                'AI extracted this bill (${(confidence * 100).round()}% confident). Tweak anything that looks off.');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}
