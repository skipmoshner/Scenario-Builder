import 'package:drift/drift.dart';

// See docs/DPE-Toolkit-Architecture.md Section 3 (CRM Core) for full
// design rationale. Every enum below is defined independently from
// FAA/general-business terminology — see DESIGN_RATIONALE.md.

enum LifecycleStage { lead, prospect, applicant, customerAlumni, lost }

enum LeadSource { referral, website, socialMedia, event, other }

enum ActivityType { call, email, meeting, note }

enum OpportunityType {
  initialCertificate,
  additionalRating,
  flightReview,
  ipc,
  groundSchool,
  ceSeminar,
  other,
}

enum OpportunityStage { identified, contacted, scheduled, completed, lost }

enum CeRequirementType { flightReview24mo, ipc, medicalRenewal, other }

enum CeStatus { upcoming, due, overdue, completed }

enum RelationshipStatus { active, inactive }

@DataClassName('Contact')
class Contacts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get fullName => text()();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  IntColumn get lifecycleStage =>
      intEnum<LifecycleStage>().withDefault(const Constant(0))();
  IntColumn get leadSource => intEnum<LeadSource>().nullable()();
  // Self-referencing FK — the scheduler/instructor who referred this contact.
  IntColumn get referredByContactId =>
      integer().nullable().references(Contacts, #id)();
  DateTimeColumn get createdDate =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastContactDate => dateTime().nullable()();
}

@DataClassName('ContactActivity')
class ContactActivities extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get contactId => integer().references(Contacts, #id)();
  IntColumn get activityType => intEnum<ActivityType>()();
  DateTimeColumn get activityDate =>
      dateTime().withDefault(currentDateAndTime)();
  TextColumn get notes => text().nullable()();
  IntColumn get relatedOpportunityId =>
      integer().nullable().references(Opportunities, #id)();
}

@DataClassName('Opportunity')
class Opportunities extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get contactId => integer().references(Contacts, #id)();
  IntColumn get opportunityType => intEnum<OpportunityType>()();
  IntColumn get stage =>
      intEnum<OpportunityStage>().withDefault(const Constant(0))();
  RealColumn get estimatedValue => real().nullable()();
  DateTimeColumn get targetDate => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
}

@DataClassName('CertificateHeld')
class CertificatesHeld extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get contactId => integer().references(Contacts, #id)();
  TextColumn get certificateRating => text()();
  DateTimeColumn get issueDate => dateTime()();
  // PII — encrypted at rest via SQLCipher on the whole DB file.
  TextColumn get certificateNumber => text().nullable()();
}

@DataClassName('ContinuingEducationRecord')
class ContinuingEducationTracking extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get contactId => integer().references(Contacts, #id)();
  IntColumn get requirementType => intEnum<CeRequirementType>()();
  DateTimeColumn get dueDate => dateTime()();
  DateTimeColumn get completedDate => dateTime().nullable()();
  IntColumn get status =>
      intEnum<CeStatus>().withDefault(const Constant(0))();
  BoolColumn get reminderSent => boolean().withDefault(const Constant(false))();
}

@DataClassName('SchedulerRole')
class SchedulerRoles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get roleName => text()();
  // True and locked for "Applicant (Self)" — core scheduling logic depends
  // on this role existing. "Recommending Instructor" / "Student Coordinator"
  // ship as editable defaults (isSystemDefault = false).
  BoolColumn get isSystemDefault =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

@DataClassName('SchedulerApplicantLink')
class SchedulerApplicantLinks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get schedulerContactId => integer().references(Contacts, #id)();
  IntColumn get applicantContactId => integer().references(Contacts, #id)();
  IntColumn get roleId => integer().references(SchedulerRoles, #id)();
  IntColumn get relationshipStatus =>
      intEnum<RelationshipStatus>().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
}
