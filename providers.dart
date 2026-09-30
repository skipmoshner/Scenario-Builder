import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database.dart';
import '../data/repositories/test_standards_repository.dart';
import '../data/repositories/scheduling_repository.dart';
import '../data/repositories/contacts_repository.dart';
import '../data/repositories/mileage_repository.dart';
import '../data/repositories/accounting_repository.dart';
import 'services/location_resolution_service.dart';
import 'services/accounting_sync_service.dart';

/// Provides the single AppDatabase instance for the app.
///
/// TODO: 'REPLACE_WITH_SECURE_PASSPHRASE' must be swapped for a passphrase
/// pulled from flutter_secure_storage or the platform keychain before this
/// ships anywhere near real applicant PII. Left explicit rather than faked
/// so it isn't missed.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(openConnection('REPLACE_WITH_SECURE_PASSPHRASE'));
  ref.onDispose(() => db.close());
  return db;
});

final testStandardsRepositoryProvider =
    Provider<TestStandardsRepository>((ref) {
  return TestStandardsRepository(ref.watch(appDatabaseProvider));
});

final schedulingRepositoryProvider = Provider<SchedulingRepository>((ref) {
  return SchedulingRepository(ref.watch(appDatabaseProvider));
});

final contactsRepositoryProvider = Provider<ContactsRepository>((ref) {
  return ContactsRepository(ref.watch(appDatabaseProvider));
});

/// Null until a real API key is wired up via LocationServiceSettings
/// (encrypted at rest). When null, MileageRepository falls back to
/// airport-only resolution + manual mileage entry — matches the
/// confirmed "API when available, manual override always possible"
/// decision rather than failing hard.
final locationResolutionServiceProvider =
    Provider<LocationResolutionService?>((ref) {
  // TODO: read the active LocationServiceSettings row and construct
  // GoogleMapsLocationService(apiKey) once secure key storage is wired up.
  return null;
});

final mileageRepositoryProvider = Provider<MileageRepository>((ref) {
  return MileageRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(locationResolutionServiceProvider),
  );
});

/// Null until QuickBooks OAuth is actually implemented — see
/// AccountingSyncService for why. AccountingRepository handles this being
/// null by throwing a clear error on sync attempts rather than failing
/// silently; CSV export works regardless, since it doesn't need this.
final accountingSyncServiceProvider = Provider<AccountingSyncService?>((ref) {
  return null;
});

final accountingRepositoryProvider = Provider<AccountingRepository>((ref) {
  return AccountingRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(accountingSyncServiceProvider),
  );
});
