import 'package:drift/drift.dart';
import '../database.dart';
import '../schema/location_services.dart';
import '../schema/accounting.dart';
import '../../core/services/location_resolution_service.dart';

/// Repository for the mileage tracker. Handles all three location input
/// types confirmed in conversation:
///   - airport identifiers: resolved against the local, bundled
///     `airports` table (public FAA NASR data — no API call)
///   - street addresses / business names: resolved via the configured
///     LocationResolutionService (Google Maps by default), with manual
///     mileage entry always available if resolution fails or isn't wanted
class MileageRepository {
  MileageRepository(this._db, this._locationService);
  final AppDatabase _db;
  final LocationResolutionService? _locationService;

  Stream<List<MileageLog>> watchAllMileageLogs() =>
      (_db.select(_db.mileageLogs)
            ..orderBy([(m) => OrderingTerm.desc(m.date)]))
          .watch();

  /// Local, no-API lookup against the bundled FAA airport reference data.
  Future<Airport?> resolveAirport(String identifier) {
    return (_db.select(_db.airports)
          ..where((a) =>
              a.identifier.upper().equals(identifier.trim().toUpperCase())))
        .getSingleOrNull();
  }

  /// Resolves a single location field (street address, business name, or
  /// airport identifier) to coordinates, using the right path for each
  /// type. Returns null if resolution fails — caller should then require
  /// manual mileage entry.
  Future<LatLng?> resolveLocation(
    String rawInput,
    LocationInputType type,
  ) async {
    if (type == LocationInputType.airportIdentifier) {
      final airport = await resolveAirport(rawInput);
      if (airport == null) return null;
      return LatLng(airport.latitude, airport.longitude);
    }

    // Street address or business name — goes through the geocoding
    // service if one is configured; otherwise resolution simply fails
    // and the UI falls back to manual entry.
    if (_locationService == null) return null;
    return _locationService.geocode(rawInput);
  }

  /// Attempts full API-based resolution (geocode both ends, then get
  /// driving distance). Returns null if any step fails — the UI should
  /// then prompt for manual mileage entry rather than blocking the record.
  Future<double?> attemptAutoCalculateMiles({
    required String startLocation,
    required LocationInputType startType,
    required String endLocation,
    required LocationInputType endType,
  }) async {
    final start = await resolveLocation(startLocation, startType);
    final end = await resolveLocation(endLocation, endType);
    if (start == null || end == null) return null;
    if (_locationService == null) return null;
    return _locationService.drivingDistanceMiles(start, end);
  }

  /// Creates the mileage log record and its corresponding
  /// accounting_sync_queue entry (per the architecture doc's isolation
  /// logic — every mileage record generates a queue entry, defaulting to
  /// include_in_sync = true).
  Future<int> createMileageLog({
    required DateTime date,
    required String startLocation,
    required LocationInputType startType,
    required String endLocation,
    required LocationInputType endType,
    required double miles,
    required DistanceSource distanceSource,
    required double rateApplied,
    String? purpose,
    int? contactId,
  }) async {
    final startCoords = await resolveLocation(startLocation, startType);
    final endCoords = await resolveLocation(endLocation, endType);
    final deduction = miles * rateApplied;

    return _db.transaction(() async {
      final mileageId = await _db.into(_db.mileageLogs).insert(
            MileageLogsCompanion.insert(
              date: date,
              startLocation: startLocation,
              startLocationType: startType,
              startLatitude: Value(startCoords?.latitude),
              startLongitude: Value(startCoords?.longitude),
              endLocation: endLocation,
              endLocationType: endType,
              endLatitude: Value(endCoords?.latitude),
              endLongitude: Value(endCoords?.longitude),
              purpose: Value(purpose),
              contactId: Value(contactId),
              miles: miles,
              distanceSource: distanceSource,
              rateApplied: rateApplied,
              computedDeduction: deduction,
            ),
          );

      await _db.into(_db.accountingSyncQueue).insert(
            AccountingSyncQueueCompanion.insert(
              sourceTable: SyncSourceTable.mileageLogs,
              sourceId: mileageId,
              contactId: Value(contactId),
              amount: deduction,
              transactionDate: date,
              category: const Value('Mileage Deduction'),
            ),
          );

      return mileageId;
    });
  }

  // --- Airport reference data management ---

  Stream<List<Airport>> watchAllAirports() =>
      _db.select(_db.airports).watch();

  /// Bulk-loads FAA public airport reference data (NASR). Intended to be
  /// called from a one-time import (CSV/JSON built from FAA's published
  /// data), not entered by hand. Upserts on identifier so re-running an
  /// import on a new 28-day cycle just refreshes coordinates.
  Future<void> importAirports(List<AirportsCompanion> airports) async {
    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(_db.airports, airports);
    });
  }
}
