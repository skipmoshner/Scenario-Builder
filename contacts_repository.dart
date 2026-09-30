import 'package:drift/drift.dart';
import '../database.dart';
import '../schema/contacts.dart';

/// CRM repository — see docs/DPE-Toolkit-Architecture.md Section 3.
/// Covers the full lead-to-alumni lifecycle: contacts, activities,
/// opportunities, certificates, continuing-ed tracking, and the
/// scheduler/referral relationships.
class ContactsRepository {
  ContactsRepository(this._db);
  final AppDatabase _db;

  // --- Contacts ---

  Stream<List<Contact>> watchAllContacts() =>
      _db.select(_db.contacts).watch();

  Stream<Contact?> watchContact(int contactId) =>
      (_db.select(_db.contacts)..where((c) => c.id.equals(contactId)))
          .watchSingleOrNull();

  Stream<List<Contact>> watchContactsByStage(LifecycleStage stage) =>
      (_db.select(_db.contacts)
            ..where((c) => c.lifecycleStage.equalsValue(stage)))
          .watch();

  Future<int> createContact({
    required String fullName,
    String? email,
    String? phone,
    String? address,
    LifecycleStage stage = LifecycleStage.lead,
    LeadSource? leadSource,
    int? referredByContactId,
  }) {
    return _db.into(_db.contacts).insert(
          ContactsCompanion.insert(
            fullName: fullName,
            email: Value(email),
            phone: Value(phone),
            address: Value(address),
            lifecycleStage: Value(stage),
            leadSource: Value(leadSource),
            referredByContactId: Value(referredByContactId),
          ),
        );
  }

  Future<void> updateLifecycleStage(int contactId, LifecycleStage stage) {
    return (_db.update(_db.contacts)..where((c) => c.id.equals(contactId)))
        .write(ContactsCompanion(lifecycleStage: Value(stage)));
  }

  // --- Activities ---

  Stream<List<ContactActivity>> watchActivitiesForContact(int contactId) =>
      (_db.select(_db.contactActivities)
            ..where((a) => a.contactId.equals(contactId))
            ..orderBy([(a) => OrderingTerm.desc(a.activityDate)]))
          .watch();

  Future<void> addActivity({
    required int contactId,
    required ActivityType type,
    String? notes,
  }) async {
    await _db.into(_db.contactActivities).insert(
          ContactActivitiesCompanion.insert(
            contactId: contactId,
            activityType: type,
            notes: Value(notes),
          ),
        );
    await (_db.update(_db.contacts)..where((c) => c.id.equals(contactId)))
        .write(ContactsCompanion(lastContactDate: Value(DateTime.now())));
  }

  // --- Opportunities ---

  Stream<List<Opportunity>> watchOpportunitiesForContact(int contactId) =>
      (_db.select(_db.opportunities)
            ..where((o) => o.contactId.equals(contactId)))
          .watch();

  Future<void> addOpportunity({
    required int contactId,
    required OpportunityType type,
    double? estimatedValue,
    DateTime? targetDate,
    String? notes,
  }) {
    return _db.into(_db.opportunities).insert(
          OpportunitiesCompanion.insert(
            contactId: contactId,
            opportunityType: type,
            estimatedValue: Value(estimatedValue),
            targetDate: Value(targetDate),
            notes: Value(notes),
          ),
        );
  }

  Future<void> updateOpportunityStage(int opportunityId, OpportunityStage stage) {
    return (_db.update(_db.opportunities)
          ..where((o) => o.id.equals(opportunityId)))
        .write(OpportunitiesCompanion(stage: Value(stage)));
  }

  // --- Certificates & continuing education ---

  Stream<List<CertificateHeld>> watchCertificatesForContact(int contactId) =>
      (_db.select(_db.certificatesHeld)
            ..where((c) => c.contactId.equals(contactId)))
          .watch();

  Stream<List<ContinuingEducationRecord>> watchCeTrackingForContact(
    int contactId,
  ) =>
      (_db.select(_db.continuingEducationTracking)
            ..where((r) => r.contactId.equals(contactId))
            ..orderBy([(r) => OrderingTerm.asc(r.dueDate)]))
          .watch();

  Future<void> markCeCompleted(int recordId, DateTime completedDate) {
    return (_db.update(_db.continuingEducationTracking)
          ..where((r) => r.id.equals(recordId)))
        .write(ContinuingEducationTrackingCompanion(
      completedDate: Value(completedDate),
      status: const Value(CeStatus.completed),
    ));
  }

  // --- Scheduler roles & referral relationships ---

  Stream<List<SchedulerRole>> watchActiveSchedulerRoles() =>
      (_db.select(_db.schedulerRoles)..where((r) => r.isActive.equals(true)))
          .watch();

  Stream<List<SchedulerApplicantLink>> watchLinksForScheduler(
    int schedulerContactId,
  ) =>
      (_db.select(_db.schedulerApplicantLinks)
            ..where((l) => l.schedulerContactId.equals(schedulerContactId)))
          .watch();

  /// Referral volume per scheduler — how many contacts each instructor/
  /// coordinator has referred. Computed in-memory rather than a raw SQL
  /// aggregate since this is a local, single-user dataset; simplest thing
  /// that's correct. Revisit with a real GROUP BY query if contact volume
  /// ever gets large enough for this to matter.
  Stream<Map<Contact, int>> watchReferralRollup() {
    return _db.select(_db.contacts).watch().map((allContacts) {
      final byReferrer = <int, int>{};
      for (final c in allContacts) {
        final referrerId = c.referredByContactId;
        if (referrerId != null) {
          byReferrer[referrerId] = (byReferrer[referrerId] ?? 0) + 1;
        }
      }
      final referrersById = {for (final c in allContacts) c.id: c};
      return {
        for (final entry in byReferrer.entries)
          if (referrersById[entry.key] != null)
            referrersById[entry.key]!: entry.value,
      };
    });
  }
}

