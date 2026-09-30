import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'features/test_organizer/test_organizer_screen.dart';
import 'features/scheduling/scheduling_screen.dart';
import 'features/crm/crm_screen.dart';
import 'features/mileage/mileage_screen.dart';
import 'features/expenses/expenses_screen.dart';
import 'features/accounting/accounting_sync_screen.dart';
import 'core/providers.dart';
import 'data/database.dart';
import 'data/schema/contacts.dart';
import 'data/schema/test_standards.dart';
import 'data/schema/location_services.dart';

void main() {
  runApp(const ProviderScope(child: DpeToolkitApp()));
}

class DpeToolkitApp extends ConsumerWidget {
  const DpeToolkitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'DPE/CFI Practice Toolkit',
      theme: ThemeData(useMaterial3: true),
      home: FutureBuilder(
        // Debug-only sample data so Test Organizer, Scheduling, CRM, and
        // Mileage all have something to show on first run. NOT for
        // production — this exists purely so the scaffold is visibly
        // working the first time it's launched. Remove before shipping,
        // or gate it behind a debug-mode check.
        future: _seedSampleDataIfEmpty(ref.watch(appDatabaseProvider)),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return const _HomeScreen();
        },
      ),
    );
  }
}

/// Inserts a handful of sample rows only if the contacts table is empty,
/// so re-launching the app doesn't duplicate data. Covers just enough to
/// exercise every screen: one test standard with one area/task/element,
/// one contact, and one sample airport.
Future<void> _seedSampleDataIfEmpty(AppDatabase db) async {
  final existing = await db.select(db.contacts).get();
  if (existing.isNotEmpty) return;

  await db.into(db.contacts).insert(
        ContactsCompanion.insert(
          fullName: 'Sample Applicant',
          email: const Value('applicant@example.com'),
        ),
      );

  final standardId = await db.into(db.testStandards).insert(
        TestStandardsCompanion.insert(
          certificateRating: 'Private Pilot – Airplane (Sample)',
          standardType: StandardType.acs,
          revisionDate: DateTime.now(),
          sourceReference: 'Sample seed data — replace with real ACS import',
        ),
      );

  final areaId = await db.into(db.areasOfOperation).insert(
        AreasOfOperationCompanion.insert(
          standardId: standardId,
          areaCode: 'I',
          areaTitle: 'Preflight Preparation (Sample)',
          randomDrawCount: const Value(1),
        ),
      );

  final taskId = await db.into(db.tasks).insert(
        TasksCompanion.insert(
          areaId: areaId,
          taskCode: 'A',
          taskTitle: 'Pilot Qualifications (Sample)',
        ),
      );

  await db.into(db.elements).insert(
        ElementsCompanion.insert(
          taskId: taskId,
          elementKey: 'PA.I.A.K1',
          elementType: ElementType.knowledge,
          elementDescription:
              'Certification requirements, currency, recordkeeping (sample element)',
          inclusionMode: InclusionMode.alwaysInclude,
        ),
      );

  await db.into(db.airports).insert(
        AirportsCompanion.insert(
          identifier: 'KSPI',
          airportName: 'Abraham Lincoln Capital Airport (Sample)',
          latitude: 39.8441,
          longitude: -89.6779,
          dataCycleDate: Value(DateTime.now()),
        ),
      );
}

class _HomeScreen extends StatefulWidget {
  const _HomeScreen();

  @override
  State<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeScreen> {
  int _index = 0;

  static const _screens = [
    TestOrganizerScreen(),
    SchedulingScreen(),
    CrmScreen(),
    MileageScreen(),
    ExpensesScreen(),
    AccountingSyncScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            label: 'Test Organizer',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Scheduling',
          ),
          NavigationDestination(
            icon: Icon(Icons.contacts_outlined),
            label: 'CRM',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_car_outlined),
            label: 'Mileage',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Expenses',
          ),
          NavigationDestination(
            icon: Icon(Icons.sync_outlined),
            label: 'Accounting',
          ),
        ],
      ),
    );
  }
}

