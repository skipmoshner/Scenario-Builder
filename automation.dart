import 'package:drift/drift.dart';
import 'contacts.dart';
import 'scheduling.dart';

// See docs/DPE-Toolkit-Architecture.md Section 6 (Automation). Emails send
// fully automatically on trigger — confirmed approach, no manual review
// step — so template changes should go through the in-app preview/test-send
// action before being activated (build this into the automation feature).

enum TriggerEvent {
  formSent,
  formSubmittedConfirmation,
  sessionConfirmed,
  reminderBeforeSession,
  invoiceIssued,
  paymentReceived,
  leadFollowUp,
  ceReminderDue,
  upsellOpportunity,
}

enum RecipientScope { applicantOnly, schedulerOnly, both }

enum DeliveryStatus { sent, failed, bounced }

@DataClassName('EmailTemplate')
class EmailTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get templateKey => intEnum<TriggerEvent>()();
  TextColumn get subjectLine => text()();
  TextColumn get bodyTemplate => text()(); // supports {{merge_fields}}
  IntColumn get recipientScope =>
      intEnum<RecipientScope>().withDefault(const Constant(2))();
}

@DataClassName('AutomationTrigger')
class AutomationTriggers extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get triggerEvent => intEnum<TriggerEvent>()();
  IntColumn get emailTemplateId => integer().references(EmailTemplates, #id)();
  BoolColumn get autoPopulateSchedule =>
      boolean().withDefault(const Constant(false))();
  // Lead time for reminders, e.g. 24 hours pre-session. Stored in minutes.
  IntColumn get leadTimeOffsetMinutes => integer().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

@DataClassName('EmailLogEntry')
class EmailLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get triggerId => integer().references(AutomationTriggers, #id)();
  IntColumn get contactId => integer().references(Contacts, #id)();
  IntColumn get relatedSessionId =>
      integer().nullable().references(TestSessions, #id)();
  DateTimeColumn get sentAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get deliveryStatus => intEnum<DeliveryStatus>()();
}
