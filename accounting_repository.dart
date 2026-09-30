import 'dart:io';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../database.dart';
import '../schema/accounting.dart';
import '../../core/services/accounting_sync_service.dart';

/// IRS Schedule C categories — public tax reference, not sourced from any
/// commercial product. See docs/DESIGN_RATIONALE.md.
const List<String> irsScheduleCCategories = [
  'Advertising',
  'Car and truck expenses',
  'Commissions and fees',
  'Contract labor',
  'Depreciation',
  'Insurance (other than health)',
  'Legal and professional services',
  'Office expense',
  'Rent or lease — vehicles/equipment',
  'Rent or lease — other business property',
  'Repairs and maintenance',
  'Supplies',
  'Travel',
  'Meals',
  'Utilities',
  'Other expenses',
];

/// Repository covering Expenses, the accounting_sync_queue isolation
/// logic, QuickBooks push, and CSV export — see
/// docs/DPE-Toolkit-Architecture.md Section 7.
class AccountingRepository {
  AccountingRepository(this._db, this._syncService);
  final AppDatabase _db;
  final AccountingSyncService? _syncService;

  // --- Expenses ---

  Stream<List<Expense>> watchAllExpenses() =>
      (_db.select(_db.expenses)..orderBy([(e) => OrderingTerm.desc(e.date)]))
          .watch();

  Future<int> createExpense({
    required String category,
    required double amount,
    required DateTime date,
    String? receiptPath,
    String? notes,
  }) async {
    return _db.transaction(() async {
      final expenseId = await _db.into(_db.expenses).insert(
            ExpensesCompanion.insert(
              category: category,
              amount: amount,
              date: date,
              receiptPath: Value(receiptPath),
              notes: Value(notes),
            ),
          );

      await _db.into(_db.accountingSyncQueue).insert(
            AccountingSyncQueueCompanion.insert(
              sourceTable: SyncSourceTable.expenses,
              sourceId: expenseId,
              amount: amount,
              transactionDate: date,
              category: Value(category),
            ),
          );

      return expenseId;
    });
  }

  // --- Sync queue / isolation logic ---

  Stream<List<AccountingSyncQueueEntry>> watchSyncQueue() =>
      (_db.select(_db.accountingSyncQueue)
            ..orderBy([(q) => OrderingTerm.desc(q.transactionDate)]))
          .watch();

  /// The core "isolate this transaction" action — flips include_in_sync
  /// so the record never leaves the local system via either channel,
  /// while staying in the local database for the examiner's own records.
  Future<void> setIncludeInSync(int queueEntryId, bool include) {
    return (_db.update(_db.accountingSyncQueue)
          ..where((q) => q.id.equals(queueEntryId)))
        .write(AccountingSyncQueueCompanion(
      includeInSync: Value(include),
      syncStatus: Value(include ? SyncStatus.notSynced : SyncStatus.excluded),
    ));
  }

  /// Pushes every include_in_sync = true, not-yet-synced entry to
  /// QuickBooks. No-ops with a clear error if no sync service is
  /// configured — see AccountingSyncService for why this throws rather
  /// than silently doing nothing.
  Future<void> syncPendingToQuickBooks() async {
    if (_syncService == null) {
      throw StateError(
        'No QuickBooks connection configured. Connect an account_integrations '
        'row with provider = quickbooksOnline before syncing.',
      );
    }

    final pending = await (_db.select(_db.accountingSyncQueue)
          ..where((q) =>
              q.includeInSync.equals(true) &
              q.syncStatus.equalsValue(SyncStatus.notSynced)))
        .get();

    for (final entry in pending) {
      await (_db.update(_db.accountingSyncQueue)
            ..where((q) => q.id.equals(entry.id)))
          .write(const AccountingSyncQueueCompanion(
        syncStatus: Value(SyncStatus.pending),
      ));

      try {
        final externalId = await _syncService.pushTransaction(
          amount: entry.amount,
          transactionDate: entry.transactionDate,
          category: entry.category,
          sourceDescription: '${entry.sourceTable.name} #${entry.sourceId}',
        );

        await (_db.update(_db.accountingSyncQueue)
              ..where((q) => q.id.equals(entry.id)))
            .write(AccountingSyncQueueCompanion(
          syncStatus: const Value(SyncStatus.synced),
          externalTransactionId: Value(externalId),
          lastSyncedDate: Value(DateTime.now()),
        ));
      } catch (_) {
        await (_db.update(_db.accountingSyncQueue)
              ..where((q) => q.id.equals(entry.id)))
            .write(const AccountingSyncQueueCompanion(
          syncStatus: Value(SyncStatus.error),
        ));
      }
    }
  }

  // --- CSV export (independent of QuickBooks sync status — confirmed as
  // a parallel channel, not a fallback for it) ---

  /// Exports every include_in_sync = true entry within [start, end] to a
  /// CSV file, logs the export event, and returns the file path.
  Future<String> exportToCsv({
    required DateTime start,
    required DateTime end,
  }) async {
    final entries = await (_db.select(_db.accountingSyncQueue)
          ..where((q) =>
              q.includeInSync.equals(true) &
              q.transactionDate.isBiggerOrEqualValue(start) &
              q.transactionDate.isSmallerOrEqualValue(end)))
        .get();

    final buffer = StringBuffer()
      ..writeln('Date,Source,Category,Amount,Sync Status,External ID');
    for (final e in entries) {
      buffer.writeln([
        e.transactionDate.toIso8601String().split('T').first,
        '${e.sourceTable.name} #${e.sourceId}',
        _csvEscape(e.category ?? ''),
        e.amount.toStringAsFixed(2),
        e.syncStatus.name,
        e.externalTransactionId ?? '',
      ].join(','));
    }

    final dir = await getApplicationDocumentsDirectory();
    final exportsDir = Directory(p.join(dir.path, 'exports'));
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    final fileName =
        'accounting_export_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File(p.join(exportsDir.path, fileName));
    await file.writeAsString(buffer.toString());

    await _db.into(_db.csvExportLog).insert(
          CsvExportLogCompanion.insert(
            rangeStart: start,
            rangeEnd: end,
            recordCount: entries.length,
            filePath: Value(file.path),
          ),
        );

    return file.path;
  }

  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Stream<List<CsvExportLogEntry>> watchExportHistory() =>
      (_db.select(_db.csvExportLog)
            ..orderBy([(e) => OrderingTerm.desc(e.exportedAt)]))
          .watch();

  // --- Integrations ---

  Stream<List<AccountingIntegration>> watchIntegrations() =>
      _db.select(_db.accountingIntegrations).watch();
}
