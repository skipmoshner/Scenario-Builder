import 'dart:math';
import 'package:drift/drift.dart';
import '../database.dart';
import '../schema/contacts.dart';
import '../schema/test_standards.dart';
import '../schema/scheduling.dart';

/// Repository for the scheduling feature, including the confirmation-time
/// element resolution logic described in
/// docs/DPE-Toolkit-Architecture.md Section 4:
///   1. always_include elements are pulled automatically
///   2. random_include elements are drawn — fixed count per area
///      (areasOfOperation.randomDrawCount)
///   3. elements mapped to the applicant's AKR deficiencies are pulled
///   4. included_during_test elements are left for the examiner to add live
class SchedulingRepository {
  SchedulingRepository(this._db);
  final AppDatabase _db;

  /// Path A (self) or Path B (third-party scheduler) — both go through this
  /// single method, differentiated only by initiatedByContactId/RoleId.
  Future<int> createSession({
    required int contactId,
    required int standardId,
    required int initiatedByContactId,
    required int initiatedByRoleId,
    required DateTime sessionDate,
  }) {
    return _db.into(_db.testSessions).insert(
          TestSessionsCompanion.insert(
            contactId: contactId,
            standardId: standardId,
            initiatedByContactId: initiatedByContactId,
            initiatedByRoleId: initiatedByRoleId,
            sessionDate: sessionDate,
          ),
        );
  }

  Stream<List<TestSession>> watchPendingSessions() =>
      (_db.select(_db.testSessions)
            ..where((s) => s.status.equalsValue(SessionStatus.pendingConfirmation)))
          .watch();

  Stream<List<TestSession>> watchConfirmedSessions() =>
      (_db.select(_db.testSessions)
            ..where((s) => s.status.equalsValue(SessionStatus.confirmed)))
          .watch();

  /// Resolves and writes test_session_elements for a session, then flips
  /// the session to confirmed. This is the core "confirmation-time
  /// resolution logic" from the architecture doc.
  Future<void> confirmSession(int sessionId, {int? scenarioId}) async {
    await _db.transaction(() async {
      final session = await (_db.select(_db.testSessions)
            ..where((s) => s.id.equals(sessionId)))
          .getSingle();

      // The UI only offers active scenarios for the session's standard, but
      // enforce it here too — this is the one place scenario_id is written.
      // Throwing inside the transaction rolls back, so nothing is resolved.
      if (scenarioId != null) {
        final scenario = await (_db.select(_db.testScenarios)
              ..where((s) => s.id.equals(scenarioId)))
            .getSingleOrNull();
        if (scenario == null) {
          throw StateError('Scenario $scenarioId no longer exists.');
        }
        if (scenario.standardId != session.standardId) {
          throw StateError(
            'Scenario "${scenario.scenarioTitle}" belongs to a different '
            'standard than this session.',
          );
        }
        if (!scenario.isActive) {
          throw StateError(
            'Scenario "${scenario.scenarioTitle}" is archived. Restore it '
            'or choose another scenario.',
          );
        }
      }

      // Pull every element for this standard, joined through
      // tasks -> areas_of_operation, so we have area context for the
      // fixed random-draw count.
      final query = _db.select(_db.elements).join([
        innerJoin(_db.tasks, _db.tasks.id.equalsExp(_db.elements.taskId)),
        innerJoin(
          _db.areasOfOperation,
          _db.areasOfOperation.id.equalsExp(_db.tasks.areaId),
        ),
      ])
        ..where(_db.areasOfOperation.standardId.equals(session.standardId));

      final rows = await query.get();

      // Step 1 — always_include
      final alwaysInclude = rows
          .where((r) =>
              r.readTable(_db.elements).inclusionMode ==
              InclusionMode.alwaysInclude)
          .map((r) => r.readTable(_db.elements));

      for (final element in alwaysInclude) {
        await _insertSessionElement(
          sessionId,
          element.id,
          ResolvedReason.always,
        );
      }

      // Step 2 — random_include, fixed draw count per area
      final randomEligibleByArea = <int, List<AcsElement>>{};
      for (final r in rows) {
        final element = r.readTable(_db.elements);
        if (element.inclusionMode != InclusionMode.randomInclude) continue;
        final area = r.readTable(_db.areasOfOperation);
        randomEligibleByArea.putIfAbsent(area.id, () => []).add(element);
      }

      final areasById = {
        for (final r in rows) r.readTable(_db.areasOfOperation).id:
            r.readTable(_db.areasOfOperation)
      };

      final random = Random();
      for (final entry in randomEligibleByArea.entries) {
        final area = areasById[entry.key]!;
        final eligible = List<AcsElement>.from(entry.value)..shuffle(random);
        final drawCount = min(area.randomDrawCount, eligible.length);
        for (final element in eligible.take(drawCount)) {
          await _insertSessionElement(
            sessionId,
            element.id,
            ResolvedReason.randomDraw,
          );
        }
      }

      // Step 3 — AKR deficiency mapped elements
      final deficiencies = await (_db.select(_db.contactAkrDeficiencies)
            ..where((d) =>
                d.contactId.equals(session.contactId) &
                d.standardId.equals(session.standardId) &
                d.mappedElementId.isNotNull()))
          .get();

      for (final d in deficiencies) {
        await _insertSessionElement(
          sessionId,
          d.mappedElementId!,
          ResolvedReason.akrDeficiency,
        );
      }

      // Step 4 — included_during_test elements are intentionally NOT
      // inserted here; see addElementDuringTest() below for live addition.

      await (_db.update(_db.testSessions)
            ..where((s) => s.id.equals(sessionId)))
          .write(
        TestSessionsCompanion(
          status: const Value(SessionStatus.confirmed),
          scenarioId: Value(scenarioId),
        ),
      );
    });
  }

  /// Avoids inserting the same element twice for a session (e.g. an
  /// element that's both always_include-eligible in one pass and already
  /// present from an earlier partial resolution).
  Future<void> _insertSessionElement(
    int sessionId,
    int elementId,
    ResolvedReason reason,
  ) async {
    final existing = await (_db.select(_db.testSessionElements)
          ..where((se) =>
              se.sessionId.equals(sessionId) & se.elementId.equals(elementId)))
        .getSingleOrNull();
    if (existing != null) return;

    await _db.into(_db.testSessionElements).insert(
          TestSessionElementsCompanion.insert(
            sessionId: sessionId,
            elementId: elementId,
            resolvedReason: reason,
            // Default to single; examiner adjusts per element in the UI.
            questionSelectionMode: QuestionSelectionMode.single,
          ),
        );
  }

  /// Examiner adds an included_during_test element live, mid-session.
  Future<void> addElementDuringTest(int sessionId, int elementId) {
    return _insertSessionElement(
      sessionId,
      elementId,
      ResolvedReason.addedDuringTest,
    );
  }

  Future<void> setQuestionSelectionMode(
    int sessionElementId,
    QuestionSelectionMode mode,
  ) {
    return (_db.update(_db.testSessionElements)
          ..where((se) => se.id.equals(sessionElementId)))
        .write(TestSessionElementsCompanion(questionSelectionMode: Value(mode)));
  }

  Future<void> selectQuestions(
    int sessionElementId,
    List<int> questionIds,
  ) async {
    await _db.transaction(() async {
      await (_db.delete(_db.testSessionElementQuestions)
            ..where((q) => q.sessionElementId.equals(sessionElementId)))
          .go();
      for (final questionId in questionIds) {
        await _db.into(_db.testSessionElementQuestions).insert(
              TestSessionElementQuestionsCompanion.insert(
                sessionElementId: sessionElementId,
                questionId: questionId,
              ),
            );
      }
    });
  }

  /// Marks a confirmed session as completed and runs the lifecycle logic
  /// from Section 3 of the architecture doc:
  ///   - writes a certificates_held record
  ///   - auto-generates the relevant continuing_education_tracking row
  ///     (flight_review_24mo, due 24 months from issue)
  ///   - flips the contact's lifecycle_stage to customer_alumni
  /// Confirmed scoping decision: this is the only path that creates
  /// certificates_held/CE rows — CFI-only clients without a completed
  /// test_sessions record don't get them (see Section 3, "Resolved").
  Future<void> completeSession(
    int sessionId, {
    required String certificateRating,
    String? certificateNumber,
  }) async {
    await _db.transaction(() async {
      final session = await (_db.select(_db.testSessions)
            ..where((s) => s.id.equals(sessionId)))
          .getSingle();

      await (_db.update(_db.testSessions)
            ..where((s) => s.id.equals(sessionId)))
          .write(const TestSessionsCompanion(
        status: Value(SessionStatus.completed),
      ));

      final issueDate = DateTime.now();

      await _db.into(_db.certificatesHeld).insert(
            CertificatesHeldCompanion.insert(
              contactId: session.contactId,
              certificateRating: certificateRating,
              issueDate: issueDate,
              certificateNumber: Value(certificateNumber),
            ),
          );

      await _db.into(_db.continuingEducationTracking).insert(
            ContinuingEducationTrackingCompanion.insert(
              contactId: session.contactId,
              requirementType: CeRequirementType.flightReview24mo,
              dueDate: DateTime(
                issueDate.year + 2,
                issueDate.month,
                issueDate.day,
              ),
            ),
          );

      await (_db.update(_db.contacts)
            ..where((c) => c.id.equals(session.contactId)))
          .write(const ContactsCompanion(
        lifecycleStage: Value(LifecycleStage.customerAlumni),
      ));
    });
  }

  Stream<List<TestSessionElement>> watchResolvedElements(int sessionId) =>
      (_db.select(_db.testSessionElements)
            ..where((se) => se.sessionId.equals(sessionId)))
          .watch();
}
