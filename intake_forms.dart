import 'package:drift/drift.dart';
import 'contacts.dart';
import 'test_standards.dart';

// See docs/DPE-Toolkit-Architecture.md Section 5 (Scheduling Intake Form).
// PII columns below rely on whole-database SQLCipher encryption
// (see lib/data/database.dart) rather than per-column encryption.

enum FormStatus { draft, sent, returned, reconciled }

@DataClassName('SchedulingRequestForm')
class SchedulingRequestForms extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get contactId => integer().nullable().references(Contacts, #id)();
  IntColumn get standardId => integer().references(TestStandards, #id)();
  IntColumn get initiatedByContactId =>
      integer().references(Contacts, #id)();
  IntColumn get initiatedByRoleId => integer()(); // references SchedulerRoles
  IntColumn get status =>
      intEnum<FormStatus>().withDefault(const Constant(0))();
  DateTimeColumn get sentDate => dateTime().nullable()();
  DateTimeColumn get returnedDate => dateTime().nullable()();
}

@DataClassName('ContactIntakeSubmission')
class ContactIntakeSubmissions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get formId => integer().references(SchedulingRequestForms, #id)();
  TextColumn get fullName => text()();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  // PII — encrypted at rest via SQLCipher (whole DB file).
  TextColumn get governmentIdNumber => text().nullable()();
  TextColumn get medicalCertificateNumber => text().nullable()();
  DateTimeColumn get dateOfBirth => dateTime().nullable()();
  TextColumn get certificateSought => text().nullable()();
  TextColumn get rawPdfPath => text().nullable()();
  BoolColumn get reconciled => boolean().withDefault(const Constant(false))();
}
