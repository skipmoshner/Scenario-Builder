import 'package:drift/drift.dart';
import 'contacts.dart';
import 'test_standards.dart';

// See docs/DPE-Toolkit-Architecture.md Section 4 (dual-path scheduling)
// and Section 6 (automation) for full design rationale.

enum SessionStatus { pendingConfirmation, confirmed, completed, cancelled }

enum ResolvedReason { always, randomDraw, akrDeficiency, addedDuringTest }

enum QuestionSelectionMode { single, all }

enum AppointmentType { checkride, stageCheck, consult, admin }

@DataClassName('TestSession')
class TestSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get contactId => integer().references(Contacts, #id)();
  IntColumn get standardId => integer().references(TestStandards, #id)();
  IntColumn get scenarioId =>
      integer().nullable().references(TestScenarios, #id)();
  // Who initiated the scheduling request — the applicant themselves, or a
  // third-party scheduler (Recommending Instructor, Student Coordinator,
  // or any custom role). See SchedulerRoles in contacts.dart.
  IntColumn get initiatedByContactId => integer().references(Contacts, #id)();
  IntColumn get initiatedByRoleId =>
      integer().references(SchedulerRoles, #id)();
  DateTimeColumn get sessionDate => dateTime()();
  IntColumn get status =>
      intEnum<SessionStatus>().withDefault(const Constant(0))();
}

@DataClassName('TestSessionElement')
class TestSessionElements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer().references(TestSessions, #id)();
  IntColumn get elementId => integer().references(Elements, #id)();
  // Audit trail — why this element ended up in this specific test.
  IntColumn get resolvedReason => intEnum<ResolvedReason>()();
  IntColumn get questionSelectionMode => intEnum<QuestionSelectionMode>()();
}

@DataClassName('TestSessionElementQuestion')
class TestSessionElementQuestions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionElementId =>
      integer().references(TestSessionElements, #id)();
  IntColumn get questionId => integer().references(ElementQuestions, #id)();
}

@DataClassName('Appointment')
class Appointments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get contactId => integer().nullable().references(Contacts, #id)();
  IntColumn get appointmentType => intEnum<AppointmentType>()();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime()();
  TextColumn get location => text().nullable()();
}
