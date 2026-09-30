import 'package:drift/drift.dart';
import 'contacts.dart';
import 'location_services.dart';

// See docs/DPE-Toolkit-Architecture.md Section 7 (Accounting, Expenses &
// Mileage). Confirmed: QuickBooks Online API sync and CSV export both run
// in parallel, not mutually exclusive.

enum InvoiceStatus { draft, sent, paid, overdue, void_ }

enum SyncSourceTable { invoices, expenses, mileageLogs }

enum SyncStatus { notSynced, pending, synced, excluded, error }

enum AccountingProvider { quickbooksOnline, csvExport }

enum ConnectionStatus { connected, disconnected, error }

@DataClassName('Invoice')
class Invoices extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get contactId => integer().references(Contacts, #id)();
  DateTimeColumn get issueDate => dateTime()();
  IntColumn get status =>
      intEnum<InvoiceStatus>().withDefault(const Constant(0))();
}

@DataClassName('InvoiceLineItem')
class InvoiceLineItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get invoiceId => integer().references(Invoices, #id)();
  TextColumn get description => text()();
  RealColumn get amount => real()();
}

@DataClassName('Expense')
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get category => text()(); // mapped to IRS Schedule C categories
  RealColumn get amount => real()();
  DateTimeColumn get date => dateTime()();
  TextColumn get receiptPath => text().nullable()();
  TextColumn get notes => text().nullable()();
}

@DataClassName('MileageLog')
class MileageLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();

  // Raw text as entered by the examiner — a street address, a business
  // name, or an airport identifier, disambiguated by the type columns
  // below so the resolver knows which lookup path to use.
  TextColumn get startLocation => text()();
  IntColumn get startLocationType => intEnum<LocationInputType>()();
  RealColumn get startLatitude => real().nullable()();
  RealColumn get startLongitude => real().nullable()();

  TextColumn get endLocation => text()();
  IntColumn get endLocationType => intEnum<LocationInputType>()();
  RealColumn get endLatitude => real().nullable()();
  RealColumn get endLongitude => real().nullable()();

  TextColumn get purpose => text().nullable()();
  IntColumn get contactId => integer().nullable().references(Contacts, #id)();

  RealColumn get miles => real()();
  // Confirmed: routing API (actual driving distance) when both endpoints
  // resolve; manual entry always available as an override/fallback.
  IntColumn get distanceSource => intEnum<DistanceSource>()();

  RealColumn get rateApplied => real()(); // current-year IRS mileage rate
  RealColumn get computedDeduction => real()();
}

@DataClassName('AccountingSyncQueueEntry')
class AccountingSyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sourceTable => intEnum<SyncSourceTable>()();
  IntColumn get sourceId => integer()();
  IntColumn get contactId => integer().nullable().references(Contacts, #id)();
  RealColumn get amount => real()();
  DateTimeColumn get transactionDate => dateTime()();
  TextColumn get category => text().nullable()();
  // Examiner flips this to false to isolate a transaction (personal expense,
  // non-deductible item, etc.) so it never leaves the local system via
  // either sync channel. Default true.
  BoolColumn get includeInSync => boolean().withDefault(const Constant(true))();
  IntColumn get syncStatus =>
      intEnum<SyncStatus>().withDefault(const Constant(0))();
  TextColumn get externalTransactionId => text().nullable()();
  DateTimeColumn get lastSyncedDate => dateTime().nullable()();
}

@DataClassName('AccountingIntegration')
class AccountingIntegrations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get provider => intEnum<AccountingProvider>()();
  IntColumn get connectionStatus =>
      intEnum<ConnectionStatus>().withDefault(const Constant(1))();
  TextColumn get credentialsRef => text().nullable()(); // encrypted OAuth ref, QuickBooks only
  DateTimeColumn get lastSyncDate => dateTime().nullable()();
}

@DataClassName('CsvExportLogEntry')
class CsvExportLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get exportedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get rangeStart => dateTime()();
  DateTimeColumn get rangeEnd => dateTime()();
  IntColumn get recordCount => integer()();
  TextColumn get filePath => text().nullable()();
}
