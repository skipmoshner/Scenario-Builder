import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/database.dart';
import '../../data/schema/accounting.dart';
import '../../data/repositories/accounting_repository.dart';

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(accountingRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add expense',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => _AddExpenseDialog(repo: repo),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<Expense>>(
        stream: repo.watchAllExpenses(),
        builder: (context, snapshot) {
          final expenses = snapshot.data ?? [];
          if (expenses.isEmpty) {
            return const Center(child: Text('No expenses logged yet.'));
          }
          final total = expenses.fold<double>(0, (sum, e) => sum + e.amount);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${expenses.length} expenses',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text('Total: \$${total.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final e in expenses)
                      ListTile(
                        title: Text(e.category),
                        subtitle: Text(
                          '${e.date.toString().split(' ').first}'
                          '${e.notes != null ? " · ${e.notes}" : ""}',
                        ),
                        trailing: Text(
                          '\$${e.amount.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AddExpenseDialog extends StatefulWidget {
  const _AddExpenseDialog({required this.repo});
  final AccountingRepository repo;

  @override
  State<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<_AddExpenseDialog> {
  String _category = irsScheduleCCategories.first;
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _date = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Expense'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Category (IRS Schedule C)'),
            value: _category,
            items: [
              for (final c in irsScheduleCCategories)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (c) => setState(() => _category = c!),
          ),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date'),
            subtitle: Text(_date.toString().split(' ').first),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final amount = double.tryParse(_amountController.text.trim());
            if (amount == null) return;
            await widget.repo.createExpense(
              category: _category,
              amount: amount,
              date: _date,
              notes: _notesController.text.trim().isEmpty
                  ? null
                  : _notesController.text.trim(),
            );
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
