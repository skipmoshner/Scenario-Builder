import 'package:drift/drift.dart';

// Supports the mileage tracker's three input types: street address,
// business name, and airport identifier. See
// docs/DPE-Toolkit-Architecture.md Section 7 (Accounting, Expenses &
// Mileage) — this file extends that section with the location-resolution
// layer confirmed in conversation: airport identifiers resolve against a
// bundled local FAA reference table (no API needed); street addresses and
// business names resolve via a geocoding/routing API when available, with
// manual mileage entry always possible as a fallback.

enum LocationInputType { streetAddress, businessName, airportIdentifier }

enum DistanceSource { geocodedRoute, manualEntry }

enum GeocodingProvider { googleMaps }

@DataClassName('Airport')
class Airports extends Table {
  IntColumn get id => integer().autoIncrement()();
  // FAA LID, ICAO, or IATA identifier as published in FAA's public NASR
  // (National Airspace System Resources) data — bundled locally, refreshed
  // on FAA's 28-day cycle. Source: FAA public data, not any third-party
  // aggregator's proprietary database, per the clean-room guardrails.
  TextColumn get identifier => text().unique()();
  TextColumn get airportName => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  // FAA NASR data cycle this record was imported from, e.g. "2026-08-06" —
  // lets the app flag stale data and prompt a refresh.
  DateTimeColumn get dataCycleDate => dateTime().nullable()();
}

@DataClassName('LocationServiceSetting')
class LocationServiceSettings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get provider => intEnum<GeocodingProvider>()();
  // Encrypted API key reference — relies on whole-database SQLCipher
  // encryption (see lib/data/database.dart), same pattern as
  // accounting_integrations.credentialsRef.
  TextColumn get apiKeyRef => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
}
