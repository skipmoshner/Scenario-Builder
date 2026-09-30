import 'package:drift/drift.dart';
import 'contacts.dart';

// See docs/DPE-Toolkit-Architecture.md Section 4 (Test Standards & Element
// Schema) for full design rationale, including the PTS synthetic-key
// provenance note — log any new element_key convention in
// DESIGN_RATIONALE.md, not just here.

enum StandardType { acs, pts }

enum ElementType { knowledge, riskManagement, skill }

enum InclusionMode { alwaysInclude, randomInclude, akrDeficiency, includedDuringTest }

enum AkrEntryMethod { manual, ocrScan }

@DataClassName('TestStandard')
class TestStandards extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get certificateRating => text()();
  IntColumn get standardType => intEnum<StandardType>()();
  DateTimeColumn get revisionDate => dateTime()();
  TextColumn get sourceReference => text()();
}

@DataClassName('AreaOfOperation')
class AreasOfOperation extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get standardId => integer().references(TestStandards, #id)();
  TextColumn get areaCode => text()();
  TextColumn get areaTitle => text()();
  // Fixed number of random_include elements to draw from this area at
  // confirmation time — confirmed approach (not percentage-based).
  IntColumn get randomDrawCount => integer().withDefault(const Constant(0))();
}

@DataClassName('AcsTask')
class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get areaId => integer().references(AreasOfOperation, #id)();
  TextColumn get taskCode => text()();
  TextColumn get taskTitle => text()();
}

@DataClassName('AcsElement') // renamed from 'Element' -- collides with
// Flutter's own Element class (the widget-tree base class present in
// every screen via package:flutter/material.dart)
class Elements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId => integer().references(Tasks, #id)();
  // Official ACS code (e.g. "PA.I.A.K1") when standardType = acs;
  // drafted synthetic key when standardType = pts. See architecture doc
  // for the synthetic-key provenance rationale.
  TextColumn get elementKey => text()();
  IntColumn get elementType => intEnum<ElementType>()();
  TextColumn get elementDescription => text()();
  IntColumn get inclusionMode => intEnum<InclusionMode>()();
}

@DataClassName('ElementQuestion')
class ElementQuestions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get elementId => integer().references(Elements, #id)();
  TextColumn get questionText => text()();
  // 1-5, enforced at the repository/validation layer, not a hard DB check —
  // keeps room for future flexibility per architecture doc.
  IntColumn get sequence => integer()();
}

@DataClassName('ContactAkrDeficiency')
class ContactAkrDeficiencies extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get contactId => integer().references(Contacts, #id)();
  IntColumn get standardId => integer().references(TestStandards, #id)();
  TextColumn get akrCode => text()();
  IntColumn get mappedElementId =>
      integer().nullable().references(Elements, #id)();
  IntColumn get entryMethod => intEnum<AkrEntryMethod>()();
  // Path to the scanned AKR report image/PDF when entryMethod = ocrScan.
  // Kept for verification — OCR accuracy on printed test reports should
  // be spot-checked rather than trusted blindly.
  TextColumn get sourceDocumentPath => text().nullable()();
}

@DataClassName('TestScenario')
class TestScenarios extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get standardId => integer().references(TestStandards, #id)();
  TextColumn get scenarioTitle => text()();
  TextColumn get scenarioNarrative => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}
