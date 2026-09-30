import 'package:drift/drift.dart';
import '../database.dart';
import '../schema/test_standards.dart';

/// Repository for the ACS/PTS test-organizer feature.
/// See docs/DPE-Toolkit-Architecture.md Section 4.
class TestStandardsRepository {
  TestStandardsRepository(this._db);
  final AppDatabase _db;

  Stream<List<TestStandard>> watchAllStandards() =>
      _db.select(_db.testStandards).watch();

  Stream<List<AreaOfOperation>> watchAreasForStandard(int standardId) =>
      (_db.select(_db.areasOfOperation)
            ..where((a) => a.standardId.equals(standardId)))
          .watch();

  Stream<List<AcsTask>> watchTasksForArea(int areaId) =>
      (_db.select(_db.tasks)..where((t) => t.areaId.equals(areaId))).watch();

  Stream<List<AcsElement>> watchElementsForTask(int taskId) =>
      (_db.select(_db.elements)..where((e) => e.taskId.equals(taskId)))
          .watch();

  Future<void> updateInclusionMode(int elementId, InclusionMode mode) {
    return (_db.update(_db.elements)..where((e) => e.id.equals(elementId)))
        .write(ElementsCompanion(inclusionMode: Value(mode)));
  }

  Future<void> updateRandomDrawCount(int areaId, int count) {
    return (_db.update(_db.areasOfOperation)
          ..where((a) => a.id.equals(areaId)))
        .write(AreasOfOperationCompanion(randomDrawCount: Value(count)));
  }

  Stream<List<ElementQuestion>> watchQuestionsForElement(int elementId) =>
      (_db.select(_db.elementQuestions)
            ..where((q) => q.elementId.equals(elementId))
            ..orderBy([(q) => OrderingTerm.asc(q.sequence)]))
          .watch();

  /// Adds a question for an element. Enforces the 5-question ceiling from
  /// the architecture doc at the repository layer (not a hard DB
  /// constraint), so this is the one place that rule needs to stay correct.
  Future<void> addQuestion(int elementId, String questionText) async {
    final existing = await (_db.select(_db.elementQuestions)
          ..where((q) => q.elementId.equals(elementId)))
        .get();

    if (existing.length >= 5) {
      throw StateError(
        'Element $elementId already has the maximum of 5 questions.',
      );
    }

    await _db.into(_db.elementQuestions).insert(
          ElementQuestionsCompanion.insert(
            elementId: elementId,
            questionText: questionText,
            sequence: existing.length + 1,
          ),
        );
  }

  Stream<List<TestScenario>> watchScenariosForStandard(int standardId) =>
      (_db.select(_db.testScenarios)
            ..where((s) => s.standardId.equals(standardId) & s.isActive.equals(true)))
          .watch();

  /// Includes archived scenarios — for the scenario management screen.
  /// Scheduling uses watchScenariosForStandard above, which hides them.
  Stream<List<TestScenario>> watchAllScenariosForStandard(int standardId) =>
      (_db.select(_db.testScenarios)
            ..where((s) => s.standardId.equals(standardId))
            ..orderBy([(s) => OrderingTerm.asc(s.scenarioTitle)]))
          .watch();

  Future<void> addScenario({
    required int standardId,
    required String title,
    required String narrative,
    bool isActive = true,
  }) {
    return _db.into(_db.testScenarios).insert(
          TestScenariosCompanion.insert(
            standardId: standardId,
            scenarioTitle: title,
            scenarioNarrative: narrative,
            isActive: Value(isActive),
          ),
        );
  }

  Future<void> updateScenario(
    int scenarioId, {
    required String title,
    required String narrative,
    required bool isActive,
  }) {
    return (_db.update(_db.testScenarios)
          ..where((s) => s.id.equals(scenarioId)))
        .write(TestScenariosCompanion(
      scenarioTitle: Value(title),
      scenarioNarrative: Value(narrative),
      isActive: Value(isActive),
    ));
  }

  /// Archive/restore. Scenarios are soft-deleted (is_active = false), never
  /// hard-deleted, because test_sessions.scenario_id references them —
  /// same convention as SchedulerRoles.
  Future<void> setScenarioActive(int scenarioId, bool isActive) {
    return (_db.update(_db.testScenarios)
          ..where((s) => s.id.equals(scenarioId)))
        .write(TestScenariosCompanion(isActive: Value(isActive)));
  }

  Future<void> deleteQuestion(int questionId) {
    return (_db.delete(_db.elementQuestions)
          ..where((q) => q.id.equals(questionId)))
        .go();
  }
}
