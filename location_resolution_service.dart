import 'dart:convert';
import 'package:http/http.dart' as http;

/// A resolved geographic point, independent of which input type produced it
/// (street address, business name search, or airport lookup).
class LatLng {
  const LatLng(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

/// Abstraction over geocoding + driving-distance lookup, so the provider
/// (Google Maps today) can be swapped without touching the mileage
/// repository or UI. Confirmed approach: API used when available, manual
/// mileage entry always possible as a fallback — see
/// docs/DPE-Toolkit-Architecture.md Section 7.
abstract class LocationResolutionService {
  /// Resolves a street address or business name to coordinates.
  /// Returns null if the API can't resolve it (network unavailable, no
  /// match, invalid key, etc.) — callers should fall back to manual entry.
  Future<LatLng?> geocode(String query);

  /// Actual driving distance in miles between two points, per the
  /// confirmed decision to use routing (not straight-line) distance for
  /// tax-deduction accuracy. Returns null on any failure.
  Future<double?> drivingDistanceMiles(LatLng origin, LatLng destination);
}

/// Google Maps implementation. Requires an API key with the Geocoding API
/// and Directions API (or the newer Routes API) enabled. The key itself
/// should come from LocationServiceSettings.apiKeyRef (encrypted via
/// SQLCipher at the database layer, same pattern as
/// accounting_integrations.credentialsRef) — never hardcode it here.
class GoogleMapsLocationService implements LocationResolutionService {
  GoogleMapsLocationService(this._apiKey);
  final String _apiKey;

  static const _geocodeBase =
      'https://maps.googleapis.com/maps/api/geocode/json';
  static const _directionsBase =
      'https://maps.googleapis.com/maps/api/directions/json';

  @override
  Future<LatLng?> geocode(String query) async {
    final uri = Uri.parse(_geocodeBase).replace(queryParameters: {
      'address': query,
      'key': _apiKey,
    });

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = body['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      final location =
          results.first['geometry']['location'] as Map<String, dynamic>;
      return LatLng(
        (location['lat'] as num).toDouble(),
        (location['lng'] as num).toDouble(),
      );
    } catch (_) {
      // Network unavailable, malformed response, etc. — caller falls back
      // to manual entry rather than surfacing a raw exception.
      return null;
    }
  }

  @override
  Future<double?> drivingDistanceMiles(
    LatLng origin,
    LatLng destination,
  ) async {
    final uri = Uri.parse(_directionsBase).replace(queryParameters: {
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'key': _apiKey,
    });

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = body['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;

      final legs = routes.first['legs'] as List<dynamic>;
      final meters =
          (legs.first['distance']['value'] as num).toDouble();
      return meters / 1609.344; // meters -> miles
    } catch (_) {
      return null;
    }
  }
}
