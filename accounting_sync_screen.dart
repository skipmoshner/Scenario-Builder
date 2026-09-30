import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/database.dart';
import '../../data/schema/accounting.dart';
import '../../data/repositories/accounting_repository.dart';

class AccountingSyncScreen extends ConsumerWidget {
  const AccountingSyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(accountingRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Accounting Sync')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Sync to QuickBooks'),
                  onPressed: () async {
                    try {
                      await repo.syncPendingToQuickBooks();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Sync complete.')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$e')),
                        );
                      }
                    }
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Export to CSV'),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => _CsvExportDialog(repo: repo),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Toggle "Include in sync" to isolate a transaction — excluded '
              'entries never leave the local system via either channel, but '
              'stay here for your own records.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: StreamBuilder<List<AccountingSyncQueueEntry>>(
              stream: repo.watchSyncQueue(),
              builder: (context, snapshot) {
                final entries = snapshot.data ?? [];
                if (entries.isEmpty) {
                  return const Center(
                    child: Text('No transactions yet. Invoices, expenses, '
                        'and mileage entries appear here automatically.'),
                  );
                }
                return ListView(
                  children: [
                    for (final entry in entries)
                      _SyncQueueTile(entry: entry, repo: repo),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncQueueTile extends StatelessWidget {
  const _SyncQueueTile({required this.entry, required this.repo});
  final AccountingSyncQueueEntry entry;
  final AccountingRepository repo;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text('${_sourceLabel(entry.sourceTable)} #${entry.sourceId}'
          '${entry.category != null ? " — ${entry.category}" : ""}'),
      subtitle: Text(
        '${entry.transactionDate.toString().split(' ').first} · '
        'Status: ${entry.syncStatus.name}'
        '${entry.externalTransactionId != null ? " · QB ID: ${entry.externalTransactionId}" : ""}',
      ),
      leading: Text(
        '\$${entry.amount.toStringAsFixed(2)}',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      trailing: Switch(
        value: entry.includeInSync,
        onChanged: (include) => repo.setIncludeInSync(entry.id, include),
      ),
    );
  }

  String _sourceLabel(SyncSourceTable table) {
    switch (table) {
      case SyncSourceTable.invoices:
        return 'Invoice';
      case SyncSourceTable.expenses:
        return 'Expense';
      case SyncSourceTable.mileageLogs:
        return 'Mileage';
    }
  }
}

class _CsvExportDialog extends StatefulWidget {
  const _CsvExportDialog({required this.repo});
  final AccountingRepository repo;

  @override
  State<_CsvExportDialog> createState() => _CsvExportDialogState();
}

class _CsvExportDialogState extends State<_CsvExportDialog> {
  DateTime _start = DateTime.now().subtract(const Duration(days: 90));
  DateTime _end = DateTime.now();
  String? _resultPath;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Export to CSV'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Start date'),
            subtitle: Text(_start.toString().split(' ').first),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _start,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _start = picked);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('End date'),
            subtitle: Text(_end.toString().split(' ').first),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _end,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _end = picked);
            },
          ),
          if (_resultPath != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Saved to: $_resultPath',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () async {
            final path = await widget.repo.exportToCsv(
              start: _start,
              end: _end,
            );
            setState(() => _resultPath = path);
          },
          child: const Text('Export'),
        ),
      ],
    );
  }
}
